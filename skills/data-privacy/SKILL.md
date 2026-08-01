---
name: data-privacy
description: How to handle files containing personal or confidential data — inspect column names and data dictionaries to classify sensitive fields, redact or pseudonymise them locally before any data enters the LLM context, and never send identifiable information to external API servers. Consult it before reading any structured data file that could contain personal data, patient records, or other confidential information.
---

# Data privacy

**Core constraint**: this agent runs on an external API (Anthropic). Any content
that enters the context window is transmitted to Anthropic's servers. Sensitive
personal data must therefore be stripped or pseudonymised *before* it enters
context — not after.

This applies to: patient records, clinical registries, genetic data, research
datasets with participant IDs, financial records with NIF/account numbers, and
any file where individuals could be identified from the data.

This skill does not apply to aggregated or already-anonymised datasets where
re-identification is not possible.

## The protocol

### Step 1 — Read only the structure, never the values

For structured files (CSV, Excel, TSV, database exports):

```python
# Python — read headers only
import pandas as pd
df = pd.read_csv("file.csv", nrows=0)   # or nrows=3 for a sample of values
print(df.columns.tolist())

# R — read headers only
cols <- names(read.csv("file.csv", nrows=0))
```

For Excel files with multiple sheets, read the sheet names first, then headers
per sheet.

**Do not read the full file** until sensitive columns have been identified and
a redaction plan is in place.

### Step 2 — Classify columns

If a **data dictionary** is available (codebook, README, REDCap instrument
export), read it first — it gives authoritative descriptions of each variable.

Otherwise, classify columns by name:

**Directly identifying (always redact/drop):**
- Names: `nombre`, `apellido`, `apellidos`, `name`, `first_name`, `last_name`,
  `full_name`, `paciente`, `patient`
- ID numbers: `nif`, `dni`, `nie`, `nhc`, `cip`, `num_historia`, `id_paciente`,
  `patient_id`, `subject_id` (unless already pseudonymised), `ssn`, `mrn`
- Contact: `email`, `correo`, `telefono`, `phone`, `direccion`, `address`,
  `cp`, `postal_code`
- Birth date: `fecha_nacimiento`, `dob`, `date_of_birth`, `birthdate`, `fnac`
- Geolocation: `lat`, `lon`, `latitude`, `longitude`, `municipio`, `localidad`
  (below regional level)

**Potentially identifying (evaluate in context):**
- `fecha_diagnostico`, `fecha_inicio`, `fecha_visita`: dates can narrow identity
  in small cohorts — consider rounding to month or year
- `hospital`, `centro`, `site`: identifying if the cohort is small
- `medico`, `neurologo`, `clinician`: name of treating physician
- Free text fields: `notas`, `comentarios`, `observaciones`, `remarks` —
  treat as identifying unless confirmed otherwise

**Safe to use as-is:**
- Scores and measurements: `alsfrs_total`, `fvc`, `peso`, `bmi`, numeric outcomes
- Categorical variables: `sexo`, `fenotipo`, `genetica` (gene name without
  patient link), `estadio`, `tratamiento` (drug name)
- Dates of study events if already pseudonymised (e.g. `days_from_onset`)
- Aggregated or derived variables

### Step 3 — Redact or pseudonymise locally

Generate and run a script that operates only on the local machine, producing a
clean output file. Only the clean file enters context.

```python
# Python — pseudonymise a clinical dataset
import pandas as pd
import hashlib

df = pd.read_csv("registro.csv")

# Drop directly identifying columns
DROP_COLS = ["nombre", "apellidos", "nif", "nhc", "email", "telefono",
             "direccion", "fecha_nacimiento"]
df = df.drop(columns=[c for c in DROP_COLS if c in df.columns])

# Pseudonymise the subject ID (keep linkage within the dataset, remove
# external linkability)
if "id_paciente" in df.columns:
    salt = "change-this-salt"  # use a fixed salt per project for consistency
    df["pid"] = df["id_paciente"].astype(str).apply(
        lambda x: hashlib.sha256((salt + x).encode()).hexdigest()[:12]
    )
    df = df.drop(columns=["id_paciente"])

# Round birth dates to year if needed
if "fecha_nacimiento" in df.columns:
    df["anyo_nacimiento"] = pd.to_datetime(df["fecha_nacimiento"]).dt.year
    df = df.drop(columns=["fecha_nacimiento"])

df.to_csv("registro_clean.csv", index=False)
print(df.shape)
print(df.columns.tolist())
```

```r
# R — pseudonymise a clinical dataset
library(dplyr)
library(digest)

df <- read.csv("registro.csv")

drop_cols <- c("nombre", "apellidos", "nif", "nhc", "email",
               "telefono", "direccion", "fecha_nacimiento")
df <- df |> select(-any_of(drop_cols))

if ("id_paciente" %in% names(df)) {
  salt <- "change-this-salt"
  df <- df |>
    mutate(pid = substr(sapply(paste0(salt, id_paciente),
                               digest, algo = "sha256"), 1, 12)) |>
    select(-id_paciente)
}

write.csv(df, "registro_clean.csv", row.names = FALSE)
cat(nrow(df), "rows,", ncol(df), "columns\n")
cat(names(df), "\n")
```

### Step 4 — Bring only the clean output into context

After the script runs, read `registro_clean.csv` (or whatever the output is).
This is the only file that enters the LLM conversation. The raw file stays on
disk, unread by the agent.

When reporting results or writing about the data, use the pseudonymised IDs
(`pid`) or ordinal references ("patient 1", "patient 2"), never original IDs.

## Data dictionaries

If the owner provides a data dictionary (codebook), read it before reading any
data file — it may reveal that columns with innocuous names contain identifying
information (e.g. a column named `code` that actually contains NHS numbers).

REDCap exports: the instrument PDF or the data dictionary CSV (`*_DataDictionary_*.csv`)
are the authoritative sources. Check `Field Label` and `Field Note` columns.

## What can safely enter context

- Summary statistics (n, mean, SD, median, IQR, proportions)
- Pseudonymised individual-level data after the protocol above
- Column names and data types (without values)
- Model outputs, scores, derived variables without direct identifiers
- Free text that has been manually reviewed by the owner and confirmed as
  non-identifying

## What cannot enter context

- Full names, initials combined with other data, or any combination that could
  re-identify a specific individual
- NHC, NIF, DNI, CIP, or any institutional identifier
- Dates of birth (use year or age in decades)
- Contact information
- Free-text clinical notes unless the owner explicitly confirms they contain
  no identifying information

## Regulatory context

Personal health data is a **special category** under GDPR (art. 9) and LOPD-GDD
(Spain). Processing it requires a legal basis (typically explicit consent or
public interest research with appropriate safeguards). The obligation not to
transmit identifiable data to third-party API providers without a data processing
agreement (DPA) is the owner's responsibility — this protocol is a technical
safeguard, not a substitute for proper data governance.

For research data, check whether the ethics committee approval covers AI-assisted
analysis and whether the DPA with the API provider (Anthropic) is in place.

## Non-structured files

PDFs of clinical reports, discharge summaries, or free-text notes: do not read
these directly. Ask the owner to provide only the specific data points needed
(manually extracted), or to confirm that the document has been de-identified
before sharing it.

Images (scans, photographs): never read directly if they could contain patient
identifiers (name overlaid on scan, visible face, ID sticker).
