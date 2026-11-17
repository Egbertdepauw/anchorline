# Blend

Where: **Gas** tab, **Blend** sub-tab.

![The Blend screen planning a Tx18/45 fill to 230 bar with helium, oxygen and air steps](images/gas-blend-1.png)

## What it's for

Works out how to fill a cylinder to a target mix. You enter the target and what is in the cylinder now, and the app computes the fill steps, the litres of each gas and a cost.

## On this screen

- **Plan band** (top): the target and pressure, then one step per gas, for example **+98 bar** helium to 98, **+19 bar** oxygen to 116 and **+114 bar** air to 230. Below the steps are the litres per gas and a total cost. Tap the cost for the breakdown. All of it is computed by the app.
- **Target**: tap a preset (Tx21/35, Tx18/45, Tx15/55, EAN32, EAN50), or type your own **O₂**, **He** and **Pressure**.
- **In the cylinder now**: **O₂**, **He**, **Pressure** and **Size** of what is already inside. You enter these.
- **Top off with**: the gas used for the last step: **Air**, **EAN32**, **EAN50** or **Other…**.
- **Role**: a control under the plan band, for example **Role Diluent (3 L)** or **Role Bailout (O2 above 32%)**. The app guesses the role: above 32% O₂ it is bailout, otherwise a cylinder up to the diluent size in the Gas settings is diluent, and a larger one is bailout. Tap it to choose **Diluent**, **Bailout**, **Backgas** or **Deco** instead. Your choice counts for this blend only; the next blend guesses again.
- **Blend mix**: records the blend you just made as an open blend and confirms it, for example "Tx18/45 added to open blends". Your entries stay on the Blend tab, ready for the next cylinder.
- **Not yet analysed (N)**: the open blends, each with a coloured dot, the mix name, the role and target pressure in bar, and how long ago you blended it (for example **1 h 05 min**). The dot is red for the first half of the **Settle time**, orange for the second half and green once it has passed. Tap the menu at the right of a row and choose **Dismiss** for a cylinder you vented or gave up on. The same count shows as a badge on the **Blend** tab.
- **Fill options**: collapsed to a summary such as "He → O₂ → top-off · real gas · 18 °C". Open it to change the **Fill order**, switch **Real-gas maths (Z)** on or off, and set **Fill temp** and **Settled temp**.

## Good to know

- If the cylinder already matches the target the plan says so. If the blend cannot be made, the plan shows the reason instead of steps.
- The plan may also tell you to drain to a pressure first, or that a hot fill settles to a lower pressure.
- An open blend stays until an analysis closes it (see [Analyse](/manual/gas-analyse)) or you dismiss it. Open blends sync to your other devices.
- The dot colour is only a hint. You can analyse a blend that is still red.
- Pressure is in bar, volume in litres, temperature in degrees Celsius.
