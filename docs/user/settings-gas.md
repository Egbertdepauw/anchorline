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

## Good to know

- Where label printing is available, a **Label printer** section appears below the analyzer settings.
- Cylinder labels are printed on a **Phomemo M110** and need **50 × 30 mm** labels (50 mm wide, 30 mm long): direct thermal gap labels, paper or synthetic ("waterproof"). Other Phomemo-compatible gap labels of that size work too. Other sizes are not supported yet.
- The prices carry no currency; they are just numbers you choose.
