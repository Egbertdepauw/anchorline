# Analyse

Where: **Gas** tab, **Analyse** sub-tab.

![The Analyse screen connected to a SOLO analyzer in Demo mode, reading Tx18.2/45.1 while settling](images/gas-analyse-1.png)

## What it's for

Shows a live reading from a Divesoft SOLO gas analyzer, works out planning values and saves the result to your gas log.

## On this screen

- **Connection strip** (top): shows **Not connected**, **Connecting…** or **SOLO connected**. Pick a source, then tap **Connect** (**Disconnect** when connected). The sources are **USB** on macOS, Windows and Linux, **USB (Android)** on Android, and **Demo**. **Demo** is a simulated analyzer for trying the screen without hardware. On iOS, Demo is the only source.
- **Readout**: **OXYGEN**, **HELIUM** and **N₂ BALANCE**, with a pill that reads **NO DATA**, **SETTLING**, **STABLE** or **SENSOR ERROR**. The analyzer measures oxygen and helium. The app computes the nitrogen balance.
- **PLANNING**: **MOD** at 1.1 (diluent), 1.4 and 1.6, then **END**, **Density**, **Min. depth**, **Gas temp** and **Ambient**. Gas temperature and ambient come from the analyzer. The rest is computed by the app.
- **Trend, last 2 minutes**: tap to open a chart of the recent readings.
- **Save analysis**: appears only with a real analyzer connected, not in Demo mode. Choose **Diluent** or **Bailout / deco**, the desired mix, a **Cylinder**, **Fill pressure**, **Analysed by** (initials), **For** and **Notes**. You enter these.
- **Save** stores the reading. **Log on OK** saves each time you press OK on the SOLO. **Save & print** also prints a label.

## Good to know

- **Save & print** and **Print a label on each OK** appear after you set up a label printer (**Set up label printer**).
- Room air is not logged on OK. Tap **Save** for it.
- An OK press before the reading is stable is saved and marked in the log.
