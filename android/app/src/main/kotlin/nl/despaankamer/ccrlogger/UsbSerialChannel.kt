package nl.despaankamer.ccrlogger

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Minimal USB CDC-ACM serial bridge for the gas analyzer (#109).
 *
 * Deliberately dependency-free: it uses only android.hardware.usb, so it
 * adds nothing to the Gradle build (the usb_serial plugin no longer builds
 * on Gradle 9, see the PR for #109). It only speaks CDC-ACM, which is what
 * the Divesoft SOLO exposes; FTDI/CP210x/CH34x adapters are out of scope.
 *
 * Method channel [METHOD_CHANNEL]:
 *  - listDevices() -> List<Map>: attached USB devices.
 *  - requestPermission(deviceName) -> Boolean: asks the user for access.
 *  - open(deviceName, baudRate) -> null: claims the CDC interfaces, sets
 *    the line coding to baudRate 8N1 and raises DTR, then starts reading.
 *    The first [STALE_DRAIN_MS] of input, up to the next line end, is
 *    discarded: the SOLO flushes lines it queued before the port was
 *    opened, and those are seconds old (#127).
 *  - close() -> null.
 *
 * Event channel [EVENT_CHANNEL]: a ByteArray per received chunk, or a map
 * {"event": "detached", "deviceName": ...} when a USB device goes away.
 */
class UsbSerialChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "nl.despaankamer.ccrlogger/usb_serial"
        const val EVENT_CHANNEL = "nl.despaankamer.ccrlogger/usb_serial/events"

        private const val ACTION_USB_PERMISSION =
            "nl.despaankamer.ccrlogger.USB_PERMISSION"

        // CDC PSTN class requests (USB CDC 1.2, PSTN120 section 6.3).
        private const val REQUEST_TYPE_CLASS_INTERFACE_OUT = 0x21
        private const val SET_LINE_CODING = 0x20
        private const val SET_CONTROL_LINE_STATE = 0x22
        private const val CONTROL_LINE_DTR = 0x01

        private const val CONTROL_TIMEOUT_MS = 1000
        private const val READ_TIMEOUT_MS = 200
        private const val STALE_DRAIN_MS = 300L
        private const val DRAIN_READ_TIMEOUT_MS = 50
        private const val LF: Byte = 0x0A
    }

    private val usbManager =
        context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var permissionReceiver: BroadcastReceiver? = null

    private var connection: UsbDeviceConnection? = null
    private var openDeviceName: String? = null
    private val claimed = mutableListOf<UsbInterface>()
    private var readThread: Thread? = null
    @Volatile private var reading = false

    private val detachReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != UsbManager.ACTION_USB_DEVICE_DETACHED) return
            val device = deviceExtra(intent) ?: return
            if (device.deviceName == openDeviceName) closeConnection()
            sink?.success(
                mapOf("event" to "detached", "deviceName" to device.deviceName)
            )
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        // ACTION_USB_DEVICE_DETACHED is a protected system broadcast, so
        // exporting the receiver doesn't let other apps fake it.
        registerReceiverCompat(
            detachReceiver,
            IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED),
            exported = true,
        )
    }

    /** Called from MainActivity.cleanUpFlutterEngine. */
    fun dispose() {
        closeConnection()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        unregisterQuietly(detachReceiver)
        permissionReceiver?.let { unregisterQuietly(it) }
        permissionReceiver = null
        pendingPermission?.success(false)
        pendingPermission = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDevices" -> result.success(
                usbManager.deviceList.values.map { describe(it) }
            )
            "requestPermission" -> requestPermission(
                call.argument<String>("deviceName"), result
            )
            "open" -> open(
                call.argument<String>("deviceName"),
                call.argument<Int>("baudRate") ?: 115200,
                result,
            )
            "close" -> {
                closeConnection()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun describe(device: UsbDevice): Map<String, Any?> {
        val interfaceClasses = (0 until device.interfaceCount).map {
            device.getInterface(it).interfaceClass
        }
        return mapOf(
            "deviceName" to device.deviceName,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceClass" to device.deviceClass,
            "interfaceClasses" to interfaceClasses,
            // Both may need permission on some OEM builds; never fail the
            // listing over a display string.
            "productName" to runCatching { device.productName }.getOrNull(),
            "manufacturerName" to
                runCatching { device.manufacturerName }.getOrNull(),
            "hasPermission" to usbManager.hasPermission(device),
        )
    }

    private fun findDevice(deviceName: String?): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { it.deviceName == deviceName }

    private fun requestPermission(deviceName: String?, result: MethodChannel.Result) {
        val device = findDevice(deviceName)
        if (device == null) {
            result.error("NOT_FOUND", "USB device $deviceName is not attached.", null)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("BUSY", "A USB permission request is already open.", null)
            return
        }
        pendingPermission = result
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != ACTION_USB_PERMISSION) return
                unregisterQuietly(this)
                permissionReceiver = null
                val granted =
                    intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                pendingPermission?.success(granted)
                pendingPermission = null
            }
        }
        permissionReceiver = receiver
        // The broadcast comes from our own PendingIntent, so the receiver
        // need not be exported.
        registerReceiverCompat(receiver, IntentFilter(ACTION_USB_PERMISSION), exported = false)
        // Explicit package + FLAG_MUTABLE: UsbManager fills in the extras,
        // and Android 14 rejects mutable PendingIntents on implicit intents.
        val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pending = PendingIntent.getBroadcast(context, 0, intent, flags)
        usbManager.requestPermission(device, pending)
    }

    private fun open(deviceName: String?, baudRate: Int, result: MethodChannel.Result) {
        closeConnection()
        val device = findDevice(deviceName)
        if (device == null) {
            result.error("NOT_FOUND", "USB device $deviceName is not attached.", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            result.error("NO_PERMISSION", "No permission for USB device $deviceName.", null)
            return
        }

        val interfaces = (0 until device.interfaceCount).map { device.getInterface(it) }
        val control = interfaces.firstOrNull {
            it.interfaceClass == UsbConstants.USB_CLASS_COMM
        }
        // Prefer the CDC data interface; fall back to any interface with a
        // bulk IN endpoint for devices that don't label theirs.
        val data = interfaces.firstOrNull {
            it.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA && bulkInEndpoint(it) != null
        } ?: interfaces.firstOrNull { bulkInEndpoint(it) != null }
        val bulkIn = data?.let { bulkInEndpoint(it) }
        if (data == null || bulkIn == null) {
            result.error("NO_DATA_INTERFACE", "USB device has no serial data interface.", null)
            return
        }

        val conn = usbManager.openDevice(device)
        if (conn == null) {
            result.error("OPEN_FAILED", "Could not open USB device $deviceName.", null)
            return
        }
        val toClaim = listOfNotNull(control, data).distinct()
        for (intf in toClaim) {
            if (!conn.claimInterface(intf, true)) {
                claimed.forEach { conn.releaseInterface(it) }
                claimed.clear()
                conn.close()
                result.error("CLAIM_FAILED", "Could not claim USB interface ${intf.id}.", null)
                return
            }
            claimed.add(intf)
        }

        // CDC class requests go to the communication interface; a device
        // without one gets them on the data interface (best effort).
        val controlIndex = (control ?: data).id
        val lineCoding = byteArrayOf(
            (baudRate and 0xff).toByte(),
            ((baudRate shr 8) and 0xff).toByte(),
            ((baudRate shr 16) and 0xff).toByte(),
            ((baudRate shr 24) and 0xff).toByte(),
            0, // 1 stop bit
            0, // no parity
            8, // 8 data bits
        )
        conn.controlTransfer(
            REQUEST_TYPE_CLASS_INTERFACE_OUT, SET_LINE_CODING, 0, controlIndex,
            lineCoding, lineCoding.size, CONTROL_TIMEOUT_MS,
        )
        conn.controlTransfer(
            REQUEST_TYPE_CLASS_INTERFACE_OUT, SET_CONTROL_LINE_STATE,
            CONTROL_LINE_DTR, controlIndex, null, 0, CONTROL_TIMEOUT_MS,
        )

        connection = conn
        openDeviceName = device.deviceName
        startReading(conn, bulkIn)
        result.success(null)
    }

    private fun bulkInEndpoint(intf: UsbInterface): UsbEndpoint? =
        (0 until intf.endpointCount).map { intf.getEndpoint(it) }.firstOrNull {
            it.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                it.direction == UsbConstants.USB_DIR_IN
        }

    private fun startReading(conn: UsbDeviceConnection, endpoint: UsbEndpoint) {
        reading = true
        readThread = Thread({
            val buffer = ByteArray(maxOf(endpoint.maxPacketSize, 64))
            // Discard the stale burst the analyzer sends on open (#127):
            // everything for STALE_DRAIN_MS, then up to the next line end
            // so the Dart side starts on a whole line.
            val drainUntil = System.nanoTime() + STALE_DRAIN_MS * 1_000_000L
            while (reading && System.nanoTime() < drainUntil) {
                conn.bulkTransfer(endpoint, buffer, buffer.size, DRAIN_READ_TIMEOUT_MS)
            }
            var synced = false
            while (reading) {
                // Returns -1 on timeout as well as on errors; detach is
                // reported by the broadcast receiver, not from here.
                val n = conn.bulkTransfer(endpoint, buffer, buffer.size, READ_TIMEOUT_MS)
                if (n <= 0) continue
                var from = 0
                if (!synced) {
                    val lf = (0 until n).firstOrNull { buffer[it] == LF } ?: continue
                    synced = true
                    from = lf + 1
                    if (from >= n) continue
                }
                val chunk = buffer.copyOfRange(from, n)
                mainHandler.post { if (reading) sink?.success(chunk) }
            }
        }, "anchorline-usb-serial-read").apply {
            isDaemon = true
            start()
        }
    }

    private fun closeConnection() {
        reading = false
        readThread?.let { runCatching { it.join(READ_TIMEOUT_MS * 2L) } }
        readThread = null
        connection?.let { conn ->
            claimed.forEach { runCatching { conn.releaseInterface(it) } }
            conn.close()
        }
        claimed.clear()
        connection = null
        openDeviceName = null
    }

    @Suppress("DEPRECATION")
    private fun deviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private fun registerReceiverCompat(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
        exported: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val flag = if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED
            context.registerReceiver(receiver, filter, flag)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun unregisterQuietly(receiver: BroadcastReceiver) {
        runCatching { context.unregisterReceiver(receiver) }
    }
}
