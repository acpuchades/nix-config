---
name: clinical-neurology
description: Clinical neurology support — drug dosing and interactions, differential diagnosis from a clinical syndrome, ALS/MND-specific clinical knowledge, and how to access reference sources (UpToDate, EAN guidelines, AEMPS/CIMA, RxNorm). Consult it whenever the owner asks about a neurological syndrome, drug dosing, a clinical decision, or patient management in the context of neurology or ALS.
---

# Clinical neurology

The owner is a clinical neurologist specialising in ALS and motor neuron disease.
This skill supports his clinical reasoning — it does not replace it. The owner
is a physician; he assumes clinical responsibility. Do not add disclaimers.

## Drug dosing and safety

Primary source: **UpToDate** (owner has access, credentials in TOOLS.md).
Secondary sources for Spanish-marketed drugs:

- **CIMA** (Centro de Información de Medicamentos de la AEMPS):
  https://cima.aemps.es — official Spanish drug database, fichas técnicas,
  prospecto, authorisation status. Publicly accessible.
- **RxNorm** (drug normalisation / interaction lookup):
  https://rxnav.nlm.nih.gov/REST/ — keyless REST API for drug names,
  RxCUI codes, and interaction data.
- **openFDA** (adverse event and label data):
  https://api.fda.gov/drug/ — adverse event reports, structured labelling.

Workflow for a dosing question:
1. Confirm the indication and patient context (renal/hepatic function, weight if
   paediatric or hepatotoxic drug, co-medications).
2. Look up in UpToDate (most complete, up-to-date for neurology).
3. Cross-reference with CIMA ficha técnica for the Spanish-marketed formulation
   (brand names and doses sometimes differ from US labelling).
4. Flag interactions with co-medications via RxNorm if the combination is
   clinically uncertain.

## Differential diagnosis from a clinical syndrome

Approach: **anatomical localisation first, aetiology second**.

### Step 1 — Localise the lesion

From the clinical syndrome (symptoms + signs + course), determine the most
likely anatomical level:

| Level | Key features |
|-------|-------------|
| Cortex / hemisphere | Cognitive/behavioural change, aphasia, hemianopia, contralateral UMN signs |
| Basal ganglia | Movement disorder (hypo- or hyperkinetic), rigidity, bradykinesia |
| Brainstem | Crossed deficits (ipsilateral CN + contralateral body), diplopia, dysarthria/dysphagia |
| Cerebellum | Ipsilateral ataxia, intention tremor, nystagmus |
| Spinal cord | Level (sensory/motor), bilateral signs, sphincter involvement |
| Anterior horn cell | Pure LMN, no sensory, fasciculations, atrophy |
| Nerve root / plexus | Dermatomal / myotomal pattern, absent reflex, pain |
| Peripheral nerve | Distal > proximal, specific nerve distribution, hypo/areflexia |
| NMJ | Fatigable weakness, ptosis, diplopia; proximal > distal; reflexes preserved |
| Muscle | Proximal weakness, preserved sensation, ± myalgia, CK elevation |

Mixed patterns (e.g. UMN + LMN at the same level) narrow the differential
significantly — in ALS, co-occurring UMN and LMN signs in the same region is
the defining feature.

### Step 2 — Structure the aetiology

For the localised syndrome, organise by VITAMIN-D:

- **V**ascular
- **I**nflammatory / immune-mediated
- **T**oxic / Traumatic
- **A**utoimmune (systemic)
- **M**etabolic / nutritional
- **I**nfectious
- **N**eoplastic (primary or metastatic)
- **D**egenerative / hereditary

For peripheral neuropathy specifically, the distribution matters:
- **Length-dependent axonal**: distal > proximal, stockings-and-gloves; typical
  causes: DM, alcohol, toxic, hereditary (HMSN), nutritional
- **Demyelinating**: slower NCVs, more proximal involvement possible; GBS (acute),
  CIDP (chronic), paraproteinaemic
- **Axonal non-length-dependent / multifocal**: mononeuritis multiplex, vasculitis,
  sarcoid, leprosy
- **Sensorimotor axonal** (the example given): DM, alcohol, uremia, toxic
  (chemotherapy, medications), hereditary, paraneoplastic — full metabolic and
  toxic screen before labelling idiopathic

### Step 3 — Workup priorities

For each differential, outline the investigations that would confirm or exclude
each hypothesis efficiently. Do not list every possible test — prioritise what
changes management.

## ALS / Motor Neuron Disease

In this context "ELA" (and equivalently "MND") refers to the **full spectrum**
of motor neuron disease — not only classic ALS but also:

| Phenotype | Spanish | Dominant feature |
|-----------|---------|-----------------|
| ALS (classic) | ELA clásica | Mixed UMN + LMN, any region |
| Progressive Bulbar Palsy | Parálisis Bulbar Progresiva (PBP) | Bulbar-onset, UMN/LMN bulbar signs |
| Flail arm syndrome | Síndrome de brazo en flagelo | Bilateral proximal arm LMN, cervical onset |
| Flail leg syndrome | Síndrome de pierna en flagelo | Bilateral distal leg LMN, lumbosacral onset |
| Progressive Muscular Atrophy | Atrofia Muscular Progresiva (AMP) | Pure LMN, no clinical UMN signs |
| Primary Lateral Sclerosis | Esclerosis Lateral Primaria (ELP) | Pure UMN, >4 years without LMN involvement |

AMP and ELP may convert to ALS over time. PBP, flail arm, and flail leg are
considered restricted ALS phenotypes with distinct prognosis — bulbar onset has
shorter survival, flail arm/leg syndromes have longer survival.

### Diagnosis

ALS/MND diagnosis is clinical, supported by electrophysiology. The current framework:
- **Gold Coast criteria** (2020, replace El Escorial/Awaji): clinical + EMG
  evidence of LMN degeneration in ≥2 regions AND UMN signs AND progressive
  course AND exclusion of other diagnoses
- Applies to the full spectrum above; AMP and ELP are diagnosed when the
  syndrome does not meet full ALS criteria but fits a recognised restricted phenotype
- EMG: active denervation (fibrillations, positive sharp waves) + chronic
  reinnervation in ≥2 regions (including at least one of bulbar, cervical,
  thoracic, lumbosacral)
- MRI to exclude structural / compressive mimics
- Screen: thyroid, B12, SPEP, anti-GM1 (for MMN), heavy metals, HIV if risk factors

### Functional assessment

**ALSFRS-R** (ALS Functional Rating Scale – Revised, TRICALS harmonized version):
48-point maximum (12 items × 0–4 each). Administered per TRICALS protocol.

| Domain | # | Item |
|--------|---|------|
| Bulbar | 1 | Speech |
| Bulbar | 2 | Salivation |
| Bulbar | 3 | Swallowing |
| Fine motor | 4 | Handwriting |
| Fine motor | 5 | Cutting food / handling utensils (use gastrostomy variant if PEG/RIG in situ) |
| Fine motor | 6 | Dressing and hygiene |
| Gross motor | 7 | Turning in bed and adjusting bed clothes |
| Gross motor | 8 | Walking |
| Gross motor | 9 | Climbing stairs |
| Respiratory | 10 | Dyspnea |
| Respiratory | 11 | Orthopnea |
| Respiratory | 12 | Respiratory insufficiency (use of respiratory support) |

Domain subscores: bulbar (items 1–3, max 12), fine motor (4–6, max 12),
gross motor (7–9, max 12), respiratory (10–12, max 12).

**Rate of decline** = (48 − score at assessment) / months since symptom onset.
This is the key prognostic metric used in trials and follow-up. A slope
> 1 point/month is generally considered fast progression.

### Multidisciplinary team

Standard of care at Bellvitge (HUB) involves:
- Neurology (diagnosis, coordination, disease-modifying treatment)
- Pneumology (respiratory monitoring, NIV initiation)
- Nutrition / dietetics (swallowing, PEG/RIG indication)
- Rehabilitation (physiotherapy, occupational therapy, speech therapy, AAC)
- Palliative care (advance care planning, symptom management)
- Social work (disability recognition, dependency aid)

### Respiratory management

NIV indication criteria (EAN guideline / AAN guideline):
- FVC < 50% predicted (seated), OR
- FVC drop > 20% from baseline, OR
- Sniff nasal inspiratory pressure (SNIP) < 40 cmH₂O, OR
- Nocturnal desaturation / morning headache / orthopnoea

### Nutrition

PEG/RIG indication: dysphagia with weight loss > 10% from diagnosis weight,
or aspiration risk. Timing matters: BMI should still be > 18 and FVC > 50% for
PEG safety (analgesia/sedation risk with respiratory compromise).

### Pharmacological treatment

**Riluzole** (only approved disease-modifying treatment in Spain):
- Dose: 50 mg twice daily
- Effect: modest survival benefit (~3 months median); best evidence in
  bulbar-onset. Mechanism: glutamate antagonism
- Side effects: nausea (start low if needed), LFT elevation (monitor at 3, 6, 12
  months then yearly)
- Interaction: avoid with CYP1A2 inducers/inhibitors (quinolones, fluvoxamine)

**Edaravone** (approved in some countries, limited access in Spain):
- IV infusion protocol; evidence mainly in a rapidly progressing subgroup
- Check current AEMPS authorisation status before discussing with patient

**Tofersen** (antisense oligonucleotide for SOD1-ALS):
- Only for confirmed pathogenic SOD1 variant
- Intrathecal injection; access via compassionate use / clinical trial in Spain
- Check ClinicalTrials.gov for active trials: https://clinicaltrials.gov

### Symptomatic management (common targets)

| Symptom | First-line option |
|---------|------------------|
| Sialorrhea | Atropine drops, hyoscine patch, botulinum toxin (parotid) |
| Pseudobulbar affect | Dextromethorphan/quinidine (Nuedexta) or amitriptyline |
| Spasticity | Baclofen (titrate slowly), tizanidine |
| Cramps | Magnesium, mexiletine (evidence in trials), quinine (limited use) |
| Insomnia / anxiety | Lorazepam (short-term), mirtazapine, melatonin |
| Pain | NSAIDs, opioids in advanced disease |
| Secretion management (late) | Mucolytics, cough-assist device, suction |

### Genetics

Offer genetic counselling when:
- Family history of ALS or FTD
- Young onset (< 50 years)
- Atypical phenotype
- Patient requests it

Common genes: C9orf72 (most frequent in Europeans), SOD1, TARDBP, FUS.
C9orf72 expansion also causes FTD — mention cognitive screening.

## Medical reports (informes de seguimiento)

When asked to draft or assist with a follow-up report, use the structure below
as the default. Adapt headings and level of detail to what the owner provides —
do not invent clinical data.

### Standard structure

**1. Descripción del seguimiento**
- Motivo del seguimiento (primer seguimiento, revisión periódica, interconsulta...)
- Fecha de inicio del seguimiento / fecha de diagnóstico
- Exploraciones complementarias realizadas desde la última visita (EMG, espirometría,
  videofluoroscopia, analítica, neuroimagen, valoración logopedia/nutrición/
  fisioterapia, ensayo clínico...)

**2. Estado actual**
- Examen físico y cognitivo en la última visita (incluir ALSFRS-R actualizado,
  MRC por grupos si procede, signos UMN/LMN relevantes, exploración bulbar)
- Evaluación funcional (cambios respecto a visita previa, velocidad de deterioro)
- Uso de recursos de soporte: VMNI, cough assist, SNG/PEG, silla de ruedas,
  comunicador, ayuda domiciliaria, reconocimiento de discapacidad
- Tratamiento farmacológico activo (riluzole, tofersen, tratamiento sintomático)
- Participación en ensayo clínico si aplica

**3. Comentarios adicionales**
Include this paragraph (or a close variant) in ALS reports:

> Se trata de una enfermedad neurodegenerativa para la que no existe actualmente
> ningún tratamiento curativo disponible. La evolución natural es de discapacidad
> progresiva e irreversible, con una esperanza de vida generalmente acortada.
> El objetivo del seguimiento multidisciplinar es optimizar la calidad de vida,
> anticipar las necesidades de soporte y respetar la autonomía del paciente en
> la toma de decisiones.

Adjust as needed — for example, if the patient is enrolled in a trial or if
palliative planning has been formally initiated, adapt the wording accordingly.

### Practical notes

- Always ask the owner to provide the clinical data — never generate clinical
  findings that have not been explicitly stated.
- If a template or previous report is shared, preserve the institutional style
  and formatting; do not impose the structure above over an existing format.
- For the functional assessment, express ALSFRS-R as total score and rate of
  decline (points/month if known) — this is the prognostically relevant metric.
- When preparing reports for the patient's file versus referral letters versus
  disability certificates, the level of technical detail and the audience differ —
  clarify before drafting.

## Key external sources

| Source | URL | Use |
|--------|-----|-----|
| UpToDate | https://www.uptodate.com | Clinical decision support (requires login) |
| CIMA/AEMPS | https://cima.aemps.es | Spanish drug authorisations and fichas técnicas |
| EAN guidelines | https://www.ean.org/guidelines | European neurology practice guidelines |
| SEN | https://www.sen.es | Spanish neurology society, national guidelines |
| ClinicalTrials.gov | https://clinicaltrials.gov | Active trials for patient referral |
| RxNorm API | https://rxnav.nlm.nih.gov | Drug normalisation, interaction lookup |
| openFDA | https://api.fda.gov/drug/ | Adverse events, drug labelling |

## What this skill is not

- It does not replace the owner's clinical judgment
- It does not produce prescriptions or modify treatment plans autonomously
- It does not have access to patient records — all clinical context must be
  provided explicitly by the owner in each query
- For genuinely complex or uncertain cases, suggest consulting a colleague or
  specialist network (ENCALS, SEN motor neuron disease group)
