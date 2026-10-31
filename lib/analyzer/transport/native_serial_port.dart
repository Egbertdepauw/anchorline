/// Minimal blocking serial port over `dart:ffi`, for the desktop analyzer
/// transport. macOS and Linux go through POSIX termios in libc, Windows
/// through the Win32 comm API in kernel32.
///
/// Why not a plugin: `flutter_libserialport` also registers an Android
/// plugin (CMake build of libserialport plus a manually applied Kotlin
/// Gradle plugin), which would change the Android build we ship. This file
/// only uses system libraries that are always present, so it adds nothing
/// to any platform build and is never touched on iOS/Android/web (the
/// analyzer screen only offers it on desktop).
///
/// Receive-only, because the SOLO only talks: 115200 baud, 8N1, no flow
/// control, DTR raised. Reads block for at most [kSerialReadTimeoutMs], so
/// a reader loop can check a stop flag between reads. Meant to run on a
/// background isolate (see `desktop_serial_transport.dart`).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Baud rate of the Divesoft SOLO.
const int kSerialBaudRate = 115200;

/// Longest a single [NativeSerialPort.read] blocks when no data arrives.
const int kSerialReadTimeoutMs = 200;

/// Thrown when a port cannot be opened or configured, or when it goes away
/// (unplugged) while reading.
class SerialPortException implements Exception {
  SerialPortException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An open serial port. Not thread-safe; use from one isolate.
abstract class NativeSerialPort {
  /// Opens [path] (`/dev/cu.usbmodem101`, `/dev/ttyACM0`, `COM3`) at
  /// [kSerialBaudRate] 8N1, no flow control, DTR raised.
  static NativeSerialPort open(String path) {
    if (Platform.isWindows) return _WindowsSerialPort.open(path);
    if (Platform.isMacOS || Platform.isLinux) return _PosixSerialPort.open(path);
    throw SerialPortException(
        'Serial ports are not supported on ${Platform.operatingSystem}.');
  }

  /// Waits up to [kSerialReadTimeoutMs] for data and returns what arrived
  /// (possibly empty). Throws [SerialPortException] when the device is
  /// gone.
  Uint8List read();

  /// Closes the port. Safe to call twice.
  void close();
}

/// Serial ports present on this machine, unfiltered (`/dev/...` paths on
/// macOS/Linux, `COMn` names on Windows). Rank them with
/// `rankSerialPorts`.
List<String> listNativeSerialPorts() {
  if (Platform.isWindows) return _listWindowsComPorts();
  if (Platform.isMacOS || Platform.isLinux) {
    try {
      return [
        for (final e in Directory('/dev').listSync(followLinks: false))
          e.path,
      ];
    } on FileSystemException {
      return const [];
    }
  }
  return const [];
}

// ---------------------------------------------------------------------------
// POSIX (macOS + Linux)
// ---------------------------------------------------------------------------

/// termios layout and constants differ between macOS (64-bit tcflag_t,
/// NCCS 20) and Linux/glibc (32-bit tcflag_t, NCCS 32). Only the fields we
/// touch are described; cfmakeraw() handles the rest.
class _PosixAbi {
  const _PosixAbi.macos()
      : cflagOffset = 16,
        cflagIs64 = true,
        ccOffset = 32,
        vmin = 16,
        vtime = 17,
        oNoctty = 0x20000,
        oNonblock = 0x4,
        csize = 0x300,
        cs8 = 0x300,
        cstopb = 0x400,
        cread = 0x800,
        parenb = 0x1000,
        hupcl = 0x4000,
        clocal = 0x8000,
        crtscts = 0x30000,
        tiocmbis = 0x8004746c,
        errnoSymbol = '__error';

  const _PosixAbi.linux()
      : cflagOffset = 8,
        cflagIs64 = false,
        ccOffset = 17,
        vmin = 6,
        vtime = 5,
        oNoctty = 0x100,
        oNonblock = 0x800,
        csize = 0x30,
        cs8 = 0x30,
        cstopb = 0x40,
        cread = 0x80,
        parenb = 0x100,
        hupcl = 0x400,
        clocal = 0x800,
        crtscts = 0x80000000,
        tiocmbis = 0x5416,
        errnoSymbol = '__errno_location';

  final int cflagOffset;
  final bool cflagIs64;
  final int ccOffset;
  final int vmin;
  final int vtime;
  final int oNoctty;
  final int oNonblock;
  final int csize;
  final int cs8;
  final int cstopb;
  final int cread;
  final int parenb;
  final int hupcl;
  final int clocal;
  final int crtscts;
  final int tiocmbis;
  final String errnoSymbol;

  static const int oRdwr = 2;
  static const int fSetfl = 4;
  static const int tcsanow = 0;
  static const int tiocmDtr = 0x002;
  static const int linuxB115200 = 0x1002;

  /// Larger than either platform's struct termios (72 / 60 bytes).
  static const int termiosBytes = 256;
}

typedef _OpenC = Int Function(Pointer<Utf8>, Int);
typedef _OpenD = int Function(Pointer<Utf8>, int);
typedef _FdC = Int Function(Int);
typedef _FdD = int Function(int);
typedef _TcGetAttrC = Int Function(Int, Pointer<Uint8>);
typedef _TcGetAttrD = int Function(int, Pointer<Uint8>);
typedef _TcSetAttrC = Int Function(Int, Int, Pointer<Uint8>);
typedef _TcSetAttrD = int Function(int, int, Pointer<Uint8>);
typedef _CfMakeRawC = Void Function(Pointer<Uint8>);
typedef _CfMakeRawD = void Function(Pointer<Uint8>);
typedef _CfSetSpeedMacC = Int Function(Pointer<Uint8>, UnsignedLong);
typedef _CfSetSpeedLinuxC = Int Function(Pointer<Uint8>, UnsignedInt);
typedef _CfSetSpeedD = int Function(Pointer<Uint8>, int);
typedef _FcntlC = Int Function(Int, Int, VarArgs<(Int,)>);
typedef _FcntlD = int Function(int, int, int);
typedef _IoctlC = Int Function(Int, UnsignedLong, VarArgs<(Pointer<Int>,)>);
typedef _IoctlD = int Function(int, int, Pointer<Int>);
typedef _ReadC = IntPtr Function(Int, Pointer<Uint8>, Size);
typedef _ReadD = int Function(int, Pointer<Uint8>, int);
typedef _ErrnoC = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();

class _Libc {
  _Libc(this.abi) : _lib = DynamicLibrary.process() {
    open = _lib.lookupFunction<_OpenC, _OpenD>('open');
    close = _lib.lookupFunction<_FdC, _FdD>('close');
    tcgetattr = _lib.lookupFunction<_TcGetAttrC, _TcGetAttrD>('tcgetattr');
    tcsetattr = _lib.lookupFunction<_TcSetAttrC, _TcSetAttrD>('tcsetattr');
    cfmakeraw = _lib.lookupFunction<_CfMakeRawC, _CfMakeRawD>('cfmakeraw');
    if (Platform.isMacOS) {
      cfsetispeed =
          _lib.lookupFunction<_CfSetSpeedMacC, _CfSetSpeedD>('cfsetispeed');
      cfsetospeed =
          _lib.lookupFunction<_CfSetSpeedMacC, _CfSetSpeedD>('cfsetospeed');
    } else {
      cfsetispeed =
          _lib.lookupFunction<_CfSetSpeedLinuxC, _CfSetSpeedD>('cfsetispeed');
      cfsetospeed =
          _lib.lookupFunction<_CfSetSpeedLinuxC, _CfSetSpeedD>('cfsetospeed');
    }
    fcntl = _lib.lookupFunction<_FcntlC, _FcntlD>('fcntl');
    ioctl = _lib.lookupFunction<_IoctlC, _IoctlD>('ioctl');
    read = _lib.lookupFunction<_ReadC, _ReadD>('read');
    _errno = _lib.lookupFunction<_ErrnoC, _ErrnoD>(abi.errnoSymbol);
  }

  final _PosixAbi abi;
  final DynamicLibrary _lib;
  late final _OpenD open;
  late final _FdD close;
  late final _TcGetAttrD tcgetattr;
  late final _TcSetAttrD tcsetattr;
  late final _CfMakeRawD cfmakeraw;
  late final _CfSetSpeedD cfsetispeed;
  late final _CfSetSpeedD cfsetospeed;
  late final _FcntlD fcntl;
  late final _IoctlD ioctl;
  late final _ReadD read;
  late final _ErrnoD _errno;

  /// Best effort: the VM may run code between the failing call and this.
  int get errno => _errno().value;
}

class _PosixSerialPort implements NativeSerialPort {
  _PosixSerialPort._(this._libc, this._path, this._fd);

  static const int _bufferSize = 4096;

  /// EAGAIN / EINTR: not an error, just no data this time.
  static final Set<int> _retryErrnos = Platform.isMacOS ? {35, 4} : {11, 4};

  final _Libc _libc;
  final String _path;
  int _fd;
  final Pointer<Uint8> _buffer = malloc<Uint8>(_bufferSize);

  /// Consecutive reads that returned 0 bytes much faster than the read
  /// timeout. A hung-up tty returns EOF immediately, forever.
  int _fastEmptyReads = 0;
  final Stopwatch _sinceExistsCheck = Stopwatch()..start();

  static _PosixSerialPort open(String path) {
    final abi = Platform.isMacOS
        ? const _PosixAbi.macos()
        : const _PosixAbi.linux();
    final libc = _Libc(abi);
    final cPath = path.toNativeUtf8();
    final termios = calloc<Uint8>(_PosixAbi.termiosBytes);
    final modem = calloc<Int>();
    var fd = -1;
    try {
      // O_NONBLOCK so open() never waits for carrier; cleared below so
      // read() honours VMIN/VTIME.
      fd = libc.open(cPath, _PosixAbi.oRdwr | abi.oNoctty | abi.oNonblock);
      if (fd < 0) {
        throw SerialPortException(
            'Could not open $path (${_describeErrno(libc.errno)}).');
      }
      if (libc.tcgetattr(fd, termios) != 0) {
        throw SerialPortException('$path is not a serial port.');
      }
      libc.cfmakeraw(termios);
      final speed =
          Platform.isMacOS ? kSerialBaudRate : _PosixAbi.linuxB115200;
      libc.cfsetispeed(termios, speed);
      libc.cfsetospeed(termios, speed);

      var cflag = _readCflag(termios, abi);
      cflag &= ~(abi.csize | abi.parenb | abi.cstopb | abi.crtscts);
      cflag |= abi.cs8 | abi.cread | abi.clocal | abi.hupcl;
      _writeCflag(termios, abi, cflag);
      // Return whatever arrived, or nothing after VTIME tenths of a second.
      termios[abi.ccOffset + abi.vmin] = 0;
      termios[abi.ccOffset + abi.vtime] = kSerialReadTimeoutMs ~/ 100;

      if (libc.tcsetattr(fd, _PosixAbi.tcsanow, termios) != 0) {
        throw SerialPortException('Could not configure $path '
            '(${_describeErrno(libc.errno)}).');
      }
      if (libc.fcntl(fd, _PosixAbi.fSetfl, 0) != 0) {
        throw SerialPortException('Could not configure $path '
            '(${_describeErrno(libc.errno)}).');
      }
      // Raise DTR. Not fatal: some drivers do not implement it.
      modem.value = _PosixAbi.tiocmDtr;
      libc.ioctl(fd, abi.tiocmbis, modem);

      final port = _PosixSerialPort._(libc, path, fd);
      fd = -1; // Owned by the port now.
      return port;
    } finally {
      if (fd >= 0) libc.close(fd);
      malloc.free(cPath);
      calloc.free(termios);
      calloc.free(modem);
    }
  }

  static int _readCflag(Pointer<Uint8> t, _PosixAbi abi) {
    final address = t.address + abi.cflagOffset;
    return abi.cflagIs64
        ? Pointer<Uint64>.fromAddress(address).value
        : Pointer<Uint32>.fromAddress(address).value;
  }

  static void _writeCflag(Pointer<Uint8> t, _PosixAbi abi, int value) {
    final address = t.address + abi.cflagOffset;
    if (abi.cflagIs64) {
      Pointer<Uint64>.fromAddress(address).value = value;
    } else {
      Pointer<Uint32>.fromAddress(address).value = value & 0xFFFFFFFF;
    }
  }

  @override
  Uint8List read() {
    if (_fd < 0) throw SerialPortException('$_path is closed.');
    final started = Stopwatch()..start();
    final n = _libc.read(_fd, _buffer, _bufferSize);
    if (n > 0) {
      _fastEmptyReads = 0;
      return Uint8List.fromList(_buffer.asTypedList(n));
    }
    if (n < 0) {
      final errno = _libc.errno;
      if (_retryErrnos.contains(errno)) return Uint8List(0);
      throw SerialPortException(
          'Lost the connection to $_path (${_describeErrno(errno)}).');
    }
    // n == 0: either the read timeout, or EOF on a hung-up device.
    if (started.elapsedMilliseconds < kSerialReadTimeoutMs ~/ 4) {
      if (++_fastEmptyReads >= 20) {
        throw SerialPortException('$_path hung up.');
      }
    } else {
      _fastEmptyReads = 0;
    }
    if (_sinceExistsCheck.elapsedMilliseconds >= 1000) {
      _sinceExistsCheck.reset();
      if (!File(_path).existsSync()) {
        throw SerialPortException('$_path disappeared.');
      }
    }
    return Uint8List(0);
  }

  @override
  void close() {
    if (_fd >= 0) {
      _libc.close(_fd);
      _fd = -1;
      malloc.free(_buffer);
    }
  }

  static String _describeErrno(int errno) => switch (errno) {
        1 => 'operation not permitted',
        2 => 'no such device',
        5 => 'I/O error',
        6 => 'device not configured',
        13 => 'permission denied',
        16 => 'device busy',
        _ => 'errno $errno',
      };
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

typedef _CreateFileC = IntPtr Function(
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr);
typedef _CreateFileD = int Function(
    Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _HandleBufC = Int32 Function(IntPtr, Pointer<Uint8>);
typedef _HandleBufD = int Function(int, Pointer<Uint8>);
typedef _HandleU32C = Int32 Function(IntPtr, Uint32);
typedef _HandleU32D = int Function(int, int);
typedef _HandleC = Int32 Function(IntPtr);
typedef _HandleD = int Function(int);
typedef _ReadFileC = Int32 Function(
    IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _ReadFileD = int Function(
    int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastErrorD = int Function();

class _WindowsSerialPort implements NativeSerialPort {
  _WindowsSerialPort._(this._name, this._handle, this._readFile,
      this._closeHandle, this._getLastError);

  static const int _genericReadWrite = 0xC0000000;
  static const int _openExisting = 3;
  static const int _invalidHandle = -1;
  static const int _setDtr = 5;
  static const int _maxDword = 0xFFFFFFFF;
  static const int _bufferSize = 4096;

  // DCB (28 bytes): DCBlength@0, BaudRate@4, flags@8, ByteSize@18,
  // Parity@19, StopBits@20.
  static const int _dcbBytes = 28;
  static const int _fBinary = 1 << 0;
  static const int _dtrControlEnable = 1 << 4;
  static const int _rtsControlEnable = 1 << 12;

  final String _name;
  int _handle;
  final _ReadFileD _readFile;
  final _HandleD _closeHandle;
  final _GetLastErrorD _getLastError;
  final Pointer<Uint8> _buffer = malloc<Uint8>(_bufferSize);
  final Pointer<Uint32> _bytesRead = malloc<Uint32>();

  static _WindowsSerialPort open(String name) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final createFile = k32.lookupFunction<_CreateFileC, _CreateFileD>(
        'CreateFileW');
    final getCommState =
        k32.lookupFunction<_HandleBufC, _HandleBufD>('GetCommState');
    final setCommState =
        k32.lookupFunction<_HandleBufC, _HandleBufD>('SetCommState');
    final setCommTimeouts =
        k32.lookupFunction<_HandleBufC, _HandleBufD>('SetCommTimeouts');
    final escapeCommFunction =
        k32.lookupFunction<_HandleU32C, _HandleU32D>('EscapeCommFunction');
    final readFile = k32.lookupFunction<_ReadFileC, _ReadFileD>('ReadFile');
    final closeHandle = k32.lookupFunction<_HandleC, _HandleD>('CloseHandle');
    final getLastError =
        k32.lookupFunction<_GetLastErrorC, _GetLastErrorD>('GetLastError');

    // `\\.\COM10` works for every port number; plain `COM10` does not.
    final devicePath = '\\\\.\\$name'.toNativeUtf16();
    final dcb = calloc<Uint8>(_dcbBytes);
    final timeouts = calloc<Uint32>(5);
    var handle = _invalidHandle;
    try {
      handle = createFile(devicePath, _genericReadWrite, 0, nullptr,
          _openExisting, 0, 0);
      if (handle == _invalidHandle || handle == 0) {
        throw SerialPortException('Could not open $name '
            '(Windows error ${getLastError()}). Is another program using it?');
      }
      Pointer<Uint32>.fromAddress(dcb.address).value = _dcbBytes;
      if (getCommState(handle, dcb) == 0) {
        throw SerialPortException('$name is not a serial port.');
      }
      final dcb32 = Pointer<Uint32>.fromAddress(dcb.address + 4);
      dcb32[0] = kSerialBaudRate; // BaudRate
      dcb32[1] = _fBinary | _dtrControlEnable | _rtsControlEnable; // flags
      dcb[18] = 8; // ByteSize
      dcb[19] = 0; // NOPARITY
      dcb[20] = 0; // ONESTOPBIT
      if (setCommState(handle, dcb) == 0) {
        throw SerialPortException('Could not configure $name '
            '(Windows error ${getLastError()}).');
      }
      // Return immediately with whatever is buffered, or wait up to the
      // read timeout for the first byte.
      timeouts[0] = _maxDword; // ReadIntervalTimeout
      timeouts[1] = _maxDword; // ReadTotalTimeoutMultiplier
      timeouts[2] = kSerialReadTimeoutMs; // ReadTotalTimeoutConstant
      timeouts[3] = 0;
      timeouts[4] = 0;
      if (setCommTimeouts(handle, timeouts.cast()) == 0) {
        throw SerialPortException('Could not configure $name '
            '(Windows error ${getLastError()}).');
      }
      escapeCommFunction(handle, _setDtr);

      final port = _WindowsSerialPort._(
          name, handle, readFile, closeHandle, getLastError);
      handle = _invalidHandle; // Owned by the port now.
      return port;
    } finally {
      if (handle != _invalidHandle && handle != 0) closeHandle(handle);
      malloc.free(devicePath);
      calloc.free(dcb);
      calloc.free(timeouts);
    }
  }

  @override
  Uint8List read() {
    if (_handle == _invalidHandle) throw SerialPortException('$_name is closed.');
    _bytesRead.value = 0;
    final ok = _readFile(_handle, _buffer, _bufferSize, _bytesRead, nullptr);
    if (ok == 0) {
      // usbser.sys fails every read once the device is unplugged.
      throw SerialPortException('Lost the connection to $_name '
          '(Windows error ${_getLastError()}).');
    }
    final n = _bytesRead.value;
    return n == 0
        ? Uint8List(0)
        : Uint8List.fromList(_buffer.asTypedList(n));
  }

  @override
  void close() {
    if (_handle != _invalidHandle) {
      _closeHandle(_handle);
      _handle = _invalidHandle;
      malloc.free(_buffer);
      malloc.free(_bytesRead);
    }
  }
}

typedef _RegOpenKeyExC = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _RegOpenKeyExD = int Function(
    int, Pointer<Utf16>, int, int, Pointer<IntPtr>);
typedef _RegEnumValueC = Int32 Function(IntPtr, Uint32, Pointer<Utf16>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>,
    Pointer<Uint32>);
typedef _RegEnumValueD = int Function(int, int, Pointer<Utf16>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>,
    Pointer<Uint32>);
typedef _RegCloseKeyC = Int32 Function(IntPtr);
typedef _RegCloseKeyD = int Function(int);

/// COM port names from `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`, which lists
/// exactly the serial ports that exist right now.
List<String> _listWindowsComPorts() {
  // HKEY_LOCAL_MACHINE is (HKEY)(LONG)0x80000002, i.e. sign-extended.
  const hkeyLocalMachine = -2147483646;
  const keyRead = 0x20019;
  const regSz = 1;
  const errorSuccess = 0;

  final adv = DynamicLibrary.open('advapi32.dll');
  final regOpenKeyEx =
      adv.lookupFunction<_RegOpenKeyExC, _RegOpenKeyExD>('RegOpenKeyExW');
  final regEnumValue =
      adv.lookupFunction<_RegEnumValueC, _RegEnumValueD>('RegEnumValueW');
  final regCloseKey =
      adv.lookupFunction<_RegCloseKeyC, _RegCloseKeyD>('RegCloseKey');

  const nameChars = 256;
  const dataBytes = 512;
  final subKey = r'HARDWARE\DEVICEMAP\SERIALCOMM'.toNativeUtf16();
  final hKey = calloc<IntPtr>();
  final name = calloc<Uint16>(nameChars);
  final nameLen = calloc<Uint32>();
  final type = calloc<Uint32>();
  final data = calloc<Uint8>(dataBytes + 2);
  final dataLen = calloc<Uint32>();
  final ports = <String>[];
  try {
    if (regOpenKeyEx(hkeyLocalMachine, subKey, 0, keyRead, hKey) !=
        errorSuccess) {
      return ports; // No serial ports at all: the key does not exist.
    }
    for (var i = 0;; i++) {
      nameLen.value = nameChars;
      dataLen.value = dataBytes;
      final rc = regEnumValue(hKey.value, i, name.cast(), nameLen, nullptr,
          type, data, dataLen);
      if (rc != errorSuccess) break; // ERROR_NO_MORE_ITEMS (259) or other.
      if (type.value != regSz) continue;
      final units = Pointer<Uint16>.fromAddress(data.address)
          .asTypedList(dataLen.value ~/ 2);
      final value = String.fromCharCodes(units.takeWhile((c) => c != 0));
      if (value.isNotEmpty) ports.add(value);
    }
    regCloseKey(hKey.value);
  } finally {
    malloc.free(subKey);
    calloc.free(hKey);
    calloc.free(name);
    calloc.free(nameLen);
    calloc.free(type);
    calloc.free(data);
    calloc.free(dataLen);
  }
  return ports;
}
