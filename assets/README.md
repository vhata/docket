# Artwork

`docket.svg` is the ledger icon; `docket.png` is its 256 × 256 raster version.
`social-preview.svg` is the editable social card; `social-preview.png` is the
1280 × 640 upload image, with an opaque background and a file size under 1 MB.

For repository link unfurls, upload `social-preview.png` at
[Settings → Social preview](https://github.com/vhata/docket/settings).
Committing the image or adding it to the README does not set GitHub's social preview.

To regenerate the PNGs with Python 3.12, CairoSVG and Cairo installed, run:

```bash
python -m cairosvg assets/docket.svg -o assets/docket.png
python -m cairosvg assets/social-preview.svg -o assets/social-preview.png
```

The card uses Georgia and Arial; install those fonts for matching typography.
