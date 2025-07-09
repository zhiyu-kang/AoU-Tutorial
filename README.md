# AoU-Tutorial
A tutorial for using All of Us platform for biomedical research.

## Description and flowchart

1. **Workspace Setup:** covering best practices for organizing and managing AoU
research workspace

2. **Cohort Identification:** outlining strategies for selecting study populations based on inclusion and exclusion criteria

3. **Clinical Variable Curation:** detailing methods for extracting and harmonizing EHR data

4. **Questionnarie and SDoH Integration:** explaining techniques for incorporating survey responses into analyses

5. **Genomic Data Utilization:** providing guidance on deriving genetic traits from whole genome sequencing (WGS) data

6. **Wearable Data Processing:** summarizing methods for processing FitBit and other wearable device data

7. **Risk Modeling:** leveraging combined outcome information from EHR and questionnaire diagnosis information


## Method

### Step 1: Workspace Setup

#### 1. Workspace Fundamentals  
- **What is a Workspace?**  
  A cloud-based environment in AoU Researcher Workbench where you create, save, and run all analyses.  
- **Key Actions on Creation:**  
  1. **Name & Discribe** your workspace, more details can be found in [Writing Your Workspace Description](https://support.researchallofus.org/hc/en-us/articles/30351591538580-Writing-Your-Workspace-Description)
  2. **Select Data Access Tier:** [Registered Tier](https://docs.google.com/document/d/158NTVpz1qJeA3_DTKAvR30XBEYhXPNqhnVQNRgK1FQM/edit?tab=t.0#heading=h.e7ppu6uf0bea) or [Control Tier](https://docs.google.com/document/d/1F3hxRgTgGc4nfQMNrsAuKwigozMKKFnV-7gU83LfI8g/edit?tab=t.0#heading=h.e7ppu6uf0bea) 
  3. **Select CDR Version** — the curated data repository (CDR) holds all current AoU research data and is updated periodically (The latest version is [CDRv8](https://support.researchallofus.org/hc/en-us/articles/30294451486356-Curated-Data-Repository-CDR-version-8-Release-Notes))
  4. **Select Billing Account** — for more details on initial credits and billing setup, see “[Paying for Your Research](https://support.researchallofus.org/hc/en-us/sections/360007074491-Paying-for-Your-Research)”

---

#### 2. Versioning & Duplication  
- **Why CDR Versioning Matters:**  
  - Ensures your results reference a fixed data snapshot.  
  - Enables others (and future you) to rerun analyses on the identical dataset.  
- **Updating Your Data:**  
  - When a new CDR is released, simply [duplicate](https://support.researchallofus.org/hc/en-us/articles/30328097309332-Managing-Workspaces) your existing workspace to inherit updated research data while preserving your original code and outputs.  

---

#### 3. Sharing & Collaboration  
- **Shared Workspace:**  Users are allowed to [share](https://support.researchallofus.org/hc/en-us/articles/30328097309332-Managing-Workspaces?utm_source=chatgpt.com) their workspace to other registered collaborators
  - including following assets: **Cohorts**, **Concept Sets**, **Datasets**, **Analysis Code**
- **Featured Workspaces:** The platform provide some example workspaces could be used as templets. More information can be found in [featured workspace](https://support.researchallofus.org/hc/en-us/articles/360059633052-Featured-Workspaces). Moreover, users are allowed to [publish](https://support.researchallofus.org/hc/en-us/articles/24058730663828-Publishing-your-workspace-as-a-Community-Workspace-in-the-Researcher-Workbench?utm_source=chatgpt.com) their workspace to as a Community Workspace.

---

#### 4. Storage Options
All of Us Researcher Workbench offers multiple storage layers. Choose the right one for your use case:

| Storage Option       | Location                                               | Persistence                            | Shared?                                 | [Access Methods](https://support.researchallofus.org/hc/en-us/articles/22465609082260-Accessing-Files-in-the-Workspace-Bucket-or-Persistent-Disk)                                             | Notes                                                                                                               |
|----------------------|--------------------------------------------------------|----------------------------------------|-----------------------------------------|------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| **Workspace Bucket** | Google Cloud Storage bucket attached to your workspace | Permanent: lives until workspace is deleted| Yes: auto-shared with collaborators | - Jupyter/RStudio file browser<br>- `gsutil ls $WORKSPACE_BUCKET`   | Ideal for long-term artifacts (scripts, summary tables, figures).     |
| **Persistent Disk**  | VM’s attached persistent disk (PD)                     | Permanent: survives VM stop/delete | No: private to you  | - VM home directory (e.g., `/home/jupyter`)<br>- Python `.to_csv()`, `.to_pickle()` | Use for software installs, config files, large intermediate data; incurs GCP storage costs.       |
| **Standard Disk**    | Ephemeral disk in Dataproc cluster environments        | Temporary: lives only with cluster       | No: isolated to that cluster          | - Dataproc notebook terminal<br>- HDFS or local shell commands              | Dataproc clusters do **not** support persistent disks; copy outputs to workspace bucket before cluster deletion.    |
> **Source:** [“Storage Options Explained”](https://support.researchallofus.org/hc/en-us/articles/5139846877844-Storage-Options-Explained), All of Us Support, updated May 14, 2025.
---
 
#### 5. Planning Your Data Strategy

| Data Modality        | Key Contents                                                             | Standard Vocabulary & OMOP Domain                                | Explore Link                                                                                                                                          |
|----------------------|---------------------------------------------------------------------------|------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| **EHR**              | conditions, drug exposures, labs and measurements, and procedures         | Conditions → Source Concpets (e.g. ICD-9,ICD-10) → Standard Concepts (e.g. SNOMED) | [Introduction to All of Us Electronic Health Record (EHR) Collection and Data Transformation Methods](https://support.researchallofus.org/hc/en-us/articles/30125602539284-Introduction-to-All-of-Us-Electronic-Health-Record-EHR-Collection-and-Data-Transformation-Methods)  |
| **Surveys**    | Self-reported demographics, lifestyle, social determinants, COVID-19      | OMOP Observation → PPI (All of Us)        | [Introduction to All of Us Survey Collection and Data Transformation Methods](https://support.researchallofus.org/hc/en-us/articles/6085114880148-Introduction-to-All-of-Us-Survey-Collection-and-Data-Transformation-Methods))   |
| **Physical Measures**| Blood pressure, heart rate, height, weight, waist circumference           | Measurement → LOINC                                              | [Introduction to All of Us Physical Measurement Data Collection and Transformation Methods](https://support.researchallofus.org/hc/en-us/articles/29888188023060-Introduction-to-All-of-Us-Physical-Measurement-Data-Collection-and-Transformation-Methods) |
| **Genomics**         | SNV/Indel calls, WGS reads, genotyping arrays                            | OMOP variant tables                                              | [Genomics](https://support.researchallofus.org/hc/en-us/articles/29475228181908-How-the-All-of-Us-Genomic-data-are-organized)|
| **Wearables**        | Activity metrics, sleep patterns, out-of-clinic heart rate               | OMOP Observation → Fitbit/PPI concepts                           | [Fitbit Data](https://support.researchallofus.org/hc/en-us/articles/20281023493908-Resources-for-Using-Fitbit-Data)   |
- For more detaisl:
  - [Data Browser](https://support.researchallofus.org/hc/en-us/articles/6088666015636-The-All-of-Us-Data-Browser-Tutorial): preview aggregate counts and distributions across domains  
  - [Data Dictionaries](https://support.researchallofus.org/hc/en-us/articles/360033200232-Data-Dictionaries) & [Codebooks](https://support.researchallofus.org/hc/en-us/articles/360051991531--All-of-Us-Survey-Codebooks):  
    - The CDR Data Dictionaries offer a complete, versioned listing of all metadata for every table and field in the All of Us CDR
    - The Survey Codebooks compile all fielded survey instruments (Baseline, Follow-Up, PPI) into a tabbed document. Each tab corresponds to one survey, listing every question, response code, value labels, and tier-specific privacy rules

---
