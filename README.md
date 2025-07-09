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
- **Personal Compute:**  
  - All analyses run in **isolated, ephemeral VMs** on the Researcher Workbench. Each user’s Jupyter, RStudio, or SAS session boots its own cloud-compute instance—ensuring resource control and securit
  - Compute instances are launched upon “Start” and destroyed on “Stop,” preventing other users’ workloads from affecting your environment
  - Only you and collaborators you explicitly share with can start or access your VM, authenticated via Login.gov and controlled by workspace sharing settings
- **Long‐term Storage:**  
  - Each workspace includes a **persistent “workspace bucket”** (Google Cloud Storage) that survives VM restarts and is deleted only when the workspace is deleted. :contentReference
  - When you share a workspace, its bucket is shared automatically, giving collaborators read/write access to all bucket files. 
  - Access bucket files via:
    - **Notebook Snippets**: Use the built-in “Cloud Storage snippets” menu in Jupyter/RStudio to list and manipulate files
    - **gsutil**: Run `gsutil ls $WORKSPACE_BUCKET` in a terminal cell to view contents
  - **Best Practice**: Store only summary tables, aggregated results, and visualizations in the bucket. Do **not** move raw participant-level data out of the CDR



---

#### 4. Planning Your Data Strategy  
- **Understand Data Modalities:**  
  - **EHR**: diagnoses, procedures, medications, labs  
  - **Surveys**: demographics, lifestyle, social determinants, COVID-19 experiences  
  - **Physical Measures**: blood pressure, heart rate, height, weight, waist circumference  
  - **Genomics**: SNV/Indel calls, WGS reads, genotyping arrays  
  - **Wearables**: activity, sleep metrics, out-of-clinic heart rate  
- **Harmonization Framework:**  
  - All data types are standardized using OMOP CDM and AoU vocabularies.  
  - Reference the `docs/reference/` folder for OMOP mapping guides and codebook details.

---

#### 5. Tools & Resources  
- **Data Browser**: preview aggregate counts and distributions across domains  
- **Data Dictionaries & Codebooks**:  
  - Provide comprehensive field definitions—indispensable for selecting the right variables  
  - Located in `docs/supplementary/codebooks/`  

---
