# GAO Relevance by Implementation Item

A review of all 190 Implementation Factory items against what GAO actually
publishes, used to derive `TOPIC_TERMS` in `index.ts`.

GAO audits **federal** programs. That single fact does most of the sorting:
an item anchored in a federal benefit program gets recurring GAO coverage, and
an item anchored in Florida law, a county program, or firm process gets none.
Two of these programs — **Medicaid** and **VA health care** — sit on GAO's
High-Risk List, which means sustained, repeated reporting rather than the
occasional study.

| Tier | Items | Meaning |
|---|---:|---|
| 1 | 91 | Recurring GAO coverage; drives `TOPIC_TERMS` |
| 2 | 13 | Occasional coverage; caught incidentally, not targeted |
| 3 | 86 | No GAO angle; deliberately out of scope |

## Tier 1 — Recurring GAO Coverage

### VA / TRICARE (22)

- **CAFC** — Program of Comprehensive Assistance for Family Caregivers
- **VACP** — VA Caregiver Program
- **VCCP** — VA Veterans Community Care Program
- **VAHC** — VA Healthcare
- **VAP** — VA Pension (Only War Time Veterans)
- **VAAA** — Veterans Benefit Administration “Low Income” Pension with Aid & Attendance
- **VDIC** — Dependency and Indemnity Compensation
- **VDC** — VA Veteran Directed Care
- **HBPC** — VA Home Based Primary Care
- **MFCH** — VA Medical Foster Care Homes
- **FVNH** — State of Florida Veterans Nursing Home
- **TDIU** — Service Connected Total Disability Award
- **VSCD** — VA Service-Connected Disability
- **VSMC** — VA Special Monthly Compensation
- **VACD** — VA Catastrophically Disabled Veteran
- **SVSD** — Survivors of Veterans Service Connected Disability
- **SURV** — Survivor of a Veteran
- **PACT** — PACT Act
- **TRIL** — TRICARE For Life
- **TRIN** — TRICARE Nursing Home
- **THCC** — TRICARE Home Health Care Coverage
- **VIAA** — VA DIC Increase in Aid & Attendance

### Medicare (18)

- **OMC** — Original Medicare
- **MCAE** — Medicare Part A Expense
- **MCBE** — Medicare Part B Expense
- **MCAP** — Medicare Part C Medicare Advantage Plan
- **MCEP** — Medicare Ordinary and Special Enrollment Periods
- **MCPA** — Medicare Part B Premium Adjustment
- **MLEP** — Medicare Part B Late Enrollment Penalty
- **MDIS** — Medicare Advantage Disenrollment
- **CRED** — Medicare Creditable Coverage
- **DSNP** — Medicare Medicaid Dual Eligible Special Needs Plans
- **MQMB** — Medicare Qualified Medicare Beneficiary
- **QMB** — Qualified Medicare Beneficiary
- **MHCC** — Medicare Part B Home Health Care
- **MDHS** — Medicare Discharge from Hospital to SNF and Requirements for Acute Rehab Admission
- **MM10** — Bridging Medicare Medicaid ICD-10
- **HCHC** — Medicare Hospice Continuous Home Care
- **HRC** — Medicare Hospice Respite Care
- **HRHC** — Medicare Hospice Routine Home Care

### Medicaid (23)

- **ICP** — Medicaid Institutional Care Program
- **MEDS** — Medicaid for Aged and Disabled
- **MMN** — Medicaid Medically Needy
- **MSD** — Medicaid Spend Down
- **SPND** — Spend Down
- **REDE** — Redetermination
- **APP** — DCF Application or QMB Referral
- **MTPC** — Medicaid Transfers, Penalty Periods, Cure of Transfer
- **MATR** — Medicaid Allowable Transfer of Assets
- **MLPA** — Medicaid Liens, Probate Avoidance, and Operation of Law
- **MPRR** — Patient Responsibility Reconciliation
- **MWPD** — Medicaid Working People with Disabilities
- **MILO** — In Lieu of Services CMS, AHCA and MCO
- **HCBA** — Home and Community-Based Services at ALF
- **HCBH** — Home and Community-Based Services at Home
- **TRAN** — Nursing Home Transition To Home and Community-Based Services Program
- **PDO** — Participant Direction Option
- **EPSD** — Early Periodic Screening Diagnostic Treatment
- **MCPI** — Comprehensive IDD Managed Care Pilot
- **CSRA** — Community Spouse Resource Allowance
- **CSIA** — Community Spouse's Monthly Income Allowance
- **MMMA** — Minimum Monthly Maintenance Allowance
- **SRAR** — Spousal Refusal and Assignment of Rights for Support

### Social Security (9)

- **SSDI** — Social Security Disability Insurance
- **SSI** — Supplemental Security Income
- **SISM** — SSI Treatment of In-Kind Support and Maintenance
- **DAC** — Disabled Adult Children
- **SSCA** — Compassionate Allowances
- **SSRB** — Social Security Red Book
- **TKTW** — Ticket to Work Program
- **CWIC** — VR Community Work Incentives Coordinator
- **VR** — Vocational Rehabilitation

### Nursing home / LTC oversight (7)

- **NHTB** — Nursing Home To Hospital Bedhold
- **DISC** — Discharged from Nursing Home
- **TALF** — Transition to ALF
- **LTCI** — Long Term Care Insurance
- **LIPP** — LTC Insurance Partnership Policy
- **CCRC** — Continuing Care Retirement Center Entrance Fee
- **PACE** — Program for All-Inclusive Care for Elderly

### Other federal (12)

- **ABLE** — Able United
- **REVM** — Reverse Mortgage
- **HHRM** — HUD HomeReady Mortgage
- **EACR** — Elder Abuse and Exploitation Civil Remedy
- **EACV** — Elder Abuse Criminal Violations
- **FMLA** — Family and Medical Leave Act
- **M504** — 504 Rehabilitation Act
- **ADA** — Americans with Disability Act
- **TIEP** — Transition Individual Education Plan
- **WC** — Workers Compensation Health Care
- **V504** — VA 504 Rehabilitation Act Integrated Setting Requirement
- **VADA** — VA Americans with Disabilities Act

## Tier 2 — Occasional Coverage

Real federal touchpoints, but GAO reports on them irregularly. These are not
worth their own search terms; they surface when a Tier 1 term catches the same
report.

- **OHE** — VA The VHA Office of Health Equity
- **RMDI** — VA Office of Resolution Management, Diversity & Inclusion
- **VDCP** — VA The External Civil Rights Discrimination Complaints Program
- **QDRO** — Qualified Domestic Relations Order
- **SDOH** — Social Determinants of Health
- **ARPA** — Acute Rehabilitation Placement Advocacy Guide
- **DOPG** — Designation of Preneed Guardian
- **APD** — Agency for Persons with Disabilities
- **ADRC** — Aging and Disability Resource Center
- **HCE** — The Home Care for the Elderly
- **MOW** — Meals on Wheels
- **LTDI** — Long Term Disability Insurance
- **STDI** — Short Term Disability Insurance

## Tier 3 — No GAO Angle

Excluded deliberately. These fall into four groups, none of which GAO audits:

- **Florida law instruments** — homestead, wills, trusts, elective share,
  life estates, probate avoidance. State substantive law.
- **County and local programs** — HART, Sunshine Line, Hillsborough Health
  Care, Pinellas County Health Program, Meals on Wheels, Seniors in Service.
- **Florida agency process** — DCF and AHCA fair hearings, notices of
  appearance, redetermination correspondence. State administration of a
  federal program is audited at the CMS level, not the county caseworker level.
- **Firm internal and private contracts** — billing, notes, plan signing,
  promissory notes, personal service contracts, leases, verifications.

A caveat on the third group: GAO does report on *federal oversight of state
Medicaid administration*, and those reports are Tier 1 via the Medicaid terms.
What is excluded is the Florida-specific procedural layer, not the federal
scrutiny of it.

<details>
<summary>Full Tier 3 list</summary>

- 1SNT — First-Party Supplemental Needs Trust
- 3SNT — Third-Party Supplemental Needs Trust
- AA — Adult Adoption
- ADOP — Adoption
- ADU — Granny Flats ADU
- AFHA — Fair Hearing Direct Reimbursement
- AFHB — AHCA Fair Hearing on Personal Care Services
- AFHC — Homemaker Services
- ALNY — Alimony
- ANOA — Notice of Appearance AHCA
- APWE — Asset Protection Widow Widower Exemption
- BANS — Billing and Notes
- BFEP — Burial Fund Exclusion Policy
- BILL — Billing
- CDCE — Child and Dependent Care Expenses
- CEIH — Child Equity Interest in Homestead
- COFS — Court Order For Support Unconnected To Divorce
- CPLN — Confirmed Plan Signing
- CTMW — Contract to Make a Will
- DBCI — Death Benefits Claim Under Insurance
- DCF4 — DCF4 Des. Rep and Releases
- DOH — Devise Of Homestead
- EPES — Estate Planning Elective Share
- EPIC — Elder Planning Income Calculator
- EPLT — Living Trust
- EPSW — Simple Will
- FINU — Financial Account Updates
- FR — Final Arrangements
- FSPA — Uniformed Services Former Spouses Protection Act
- HART — Transportation HARTPlus Paratransit
- HBHC — Hillsborough Health Care
- HCA — Health Care Advocacy
- HELC — Home Equity Line Of Credit
- HIAS — Homestead in Another State
- HOME — Homestead
- HOTC — Homestead Over The Cap
- HPTE — Homestead Property Tax Exemptions
- HRTD — HART  Regional Transportation Disadvantage
- HSIS — Seniors in Service
- HSUN — Transportation Sunshine Line Hillsborough County
- IDTP — Dependent for tax purposes
- IMED — Medical Expense Deduction
- IRFT — Irrevocable Family Trust
- KINS — Kinship Adoption
- LBCS — Loan by Community Spouse
- LDCF — Letter to DCF
- LI — Life Insurance Policy
- LIFT — Lift Chair Needed
- LITI — Litigation Advocacy
- LOAN — Loan Agreement
- MBC — Burial Contract
- MBS — Burial Spaces
- MPBP — Prepaid Burial Plan
- MPSA — Purchase Spousal Annuity
- MPSC — Personal Service Contract
- MTNL — Modified Triple Net Lease
- NCR — Name on the Check Rule
- NOTE — Notes
- NS — Natural Supports
- OLAW — Operation of Law
- PCHP — Pinellas County Health Program
- PINC — Protected Income
- PMOD — PSTA Mobility on Demand
- PN — Promissory Note
- PPBR — Prepaid Burial
- PSNT — Pooled Trust
- QFMD — IRA –  Qualified Funds Monthly Distributions
- QSNT — Last Will and Testament with a Qualified Testamentary Special Needs Trust
- RCM — Referral to Care Manager
- RECA — Real-Estate Caretaker Agreement
- RENT — Rental Property
- REVT — Revocable Trust
- RMBS — Caregiver Reimbursements
- RPOT — Reverse Pour Over QTSNT Well Spouse Revocable Trust
- RS — Reluctant Spouse
- SCST — SCS Pooled Trust
- SEIH — Sibling Equity Interest in Homestead
- SUIB — Step Up in Basis
- TLEI — Transfer of a Life Estate Interest
- VAPT — Veterans Asset Protection Trust
- VAST — Verification of Assets
- VICL — Vehicle
- VINC — Verification of Income
- VLOC — Verification of Level of Care
- WD — Winding Down
- WMOL — Written Memorialization of an Oral Loan

</details>

## What This Changed

The original `TOPIC_TERMS` was nine terms written before this review. Against
the 91 Tier 1 items it missed entire programs the firm handles: TRICARE,
hospice, Medicare Advantage and Part B/D enrollment, dual-eligible plans,
PACE, ABLE accounts, reverse mortgages, Ticket to Work, spousal
impoverishment, the PACT Act, and continuing care retirement communities.

It also searched full text, which is why a highway congestion report matched
an elder-law query on the first smoke run. GAO titles are strongly topical
("Medicaid: CMS Should Improve...", "VA Health Care: ..."), so the query is
now scoped to titles for precision.
