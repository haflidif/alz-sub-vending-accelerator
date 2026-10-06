# Brand source

`subscription-vending-source.png` is the approved icon-only source artwork for
the Subscription Vending Accelerator.

The public site does not serve this original file directly. Generate centered
and optimized derivatives with:

```powershell
python -m pip install Pillow
python ./website/scripts/build-brand-assets.py
```

Use the generated assets as follows:

- `subscription-vending-mark-512.png`: repository avatar and large placements
- `subscription-vending-mark-192.png`: high-density site header
- `subscription-vending-mark-64.png`: compact badges and previews
- `favicon-32x32.png` and `favicon-16x16.png`: browser favicons

Always regenerate derivatives from the approved source instead of editing the
smaller PNG files independently.
