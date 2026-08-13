# Strain data

The bundled catalog contains factual reference fields, not medical advice or guaranteed lab results. Potency varies by grow, harvest, batch, and laboratory.

Sources:

- Existing Sesh-curated factual profiles.
- [Kushy cannabis-dataset](https://github.com/kushyapp/cannabis-dataset), MIT licensed. Imported fields are limited to names, classification, breeder, effects, flavors, terpenes, THC, and CBD. Source prose and images are not copied.
- OpenTHC identifiers already present in the catalog follow the [OpenTHC Variety model](https://api.openthc.org/doc/openapi-html-v2/).

Run `python3 Tools/update_strain_catalog.py` to download, normalize, merge, validate, deduplicate, and alphabetize the licensed Kushy data. The updater preserves richer existing fields and rejects implausible THC/CBD values instead of presenting them as facts.
