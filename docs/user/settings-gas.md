# Gas

Where: **Settings** tab, **Gas** sub-tab.

![The Gas settings with blending prices, blend tab defaults and analyzer MOD rows](images/settings-gas-1.png)

## What it's for

Defaults for blending and analysing gas: what your fills cost, what a new blend starts with, and which limits the analyzer shows. They save you retyping the same values.

## On this screen

- **Blending prices**: **Oxygen** and **Helium** are a price per litre. **Top-off fill fee** is a price per fill of air or nitrox. They are used for the cost of a blend.
- **Blend tab starts with**: the values a new blend opens with.
  - **Top-off gas**: the oxygen and helium percentages of your top-off gas.
  - **Fill order**: the order of steps, one of **He → O₂ → top-off**, **O₂ → He → top-off** or **O₂ → top-off → He**.
  - **Real-gas maths (Z)**: when on, blends use real-gas behaviour. When off, they use the ideal gas law.
  - **Fill / settled temp**: the temperature while filling, then once the cylinder has settled, in °C.
  - **Settle time (min)**: how long a fill needs to settle before you analyse it. Open blends turn red, orange and green against it. It starts at 60 and takes 0 to 1440 minutes.
  - **Diluent cylinder up to (L)**: a cylinder with this water capacity or less, and at most 32% oxygen, is guessed as diluent on the Blend tab. It starts at 3 and takes 0.5 to 50 litres.
- **Analyzer**: **MOD rows at ppO₂** lists the ppO₂ values for which the analyzer shows a maximum operating depth. Remove one with its cross (the last one stays), or tap **+ Add** and enter a ppO₂ in bar. **Fill pressure starts at** sets the pressure a new analysis begins with, in bar.
- **Label printer**: appears where label printing is available. It shows the saved printer, or **No printer set up**, with **Find printer**, **Print test label** and **Forget printer**. Below them:
  - **Label size**: the size of the labels in the printer, one of **50 × 30 mm**, **40 × 30 mm**, **50 × 50 mm** and **50 × 80 mm** (width × length). Every label you print is drawn for this size.
  - **Rotate centre on 50 × 80**: shown only for the 50 × 80 mm size. It turns the big depth 90° counterclockwise (it reads from the bottom up) so it can be larger. Off by default.
  - **Use 1.4 for deeper mixes**: bailout and deco labels show the depth at ppO₂ 1.4 for mixes below 50 % O₂. Off: 1.6 for all.
  - **OC working ppO₂**: **1.3** or **1.4**, the ppO₂ for the big depth on **Backgas** labels. It starts at 1.4.

## Good to know

- Where label printing is available, a **Label printer** section appears below the analyzer settings.
- Cylinder labels are printed on a **Phomemo M110** on direct thermal gap labels, paper or synthetic ("waterproof"). Four sizes work: **50 × 30 mm** (the default), **40 × 30 mm**, **50 × 50 mm** and **50 × 80 mm**. Load labels of one size and pick the same size under **Label size** in the **Label printer** section; the app does not detect the roll. Other Phomemo-compatible gap labels of these sizes work too.
- The **40 × 30 mm** label is printed centred under the print head. That has not been checked on a printer yet; if the print sits against one side, tell us.
- A **Backgas** label shows an **OC** tag and the depth at the **OC working ppO₂** as the big number, with the MOD at ppO₂ 1.6 below it. Bailout and deco labels show one big MOD; diluent labels show **DIL** and three depths.
- The prices carry no currency; they are just numbers you choose.
