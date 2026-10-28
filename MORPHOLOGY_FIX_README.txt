ALQARIAPP MORPHOLOGY FORMAT FIX

This update fixes two related compatibility problems:
1) scripts/fetch_data.py no longer assumes that the morphology source has a LOCATION header and parenthesized location records near the top of the file.
2) lib/main.dart accepts location identifiers with or without parentheses.

Install this patch by extracting this project ZIP into the parent folder containing your existing AlQari_Full directory and choosing Replace files when prompted. DO NOT delete the existing .git folder.

Then open PowerShell in the existing project folder and run:
  git add scripts/fetch_data.py lib/main.dart MORPHOLOGY_FIX_README.txt
  git commit -m "Fix morphology corpus format validation"
  git push

The push should trigger GitHub Actions again. If it still fails, open the new run and share the first red step's full log.
