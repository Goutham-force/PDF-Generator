# PDF Generator - Salesforce LWC Project

## Features
- Multi-step form (Opportunity selection + Line Items)
- Add multiple line items dynamically
- Automatic total calculation
- Save Invoice and Line Items using Apex
- PDF generation and download
- Quick Action on Opportunity

## Setup Steps
1. Create Scratch Org:
   sfdx force:org:create -s -f config/project-scratch-def.json -a PDFApp

2. Push Source:
   sfdx force:source:push

3. Open Org:
   sfdx force:org:open

## Test Data
- Create an Opportunity record
- Use "Create Invoice" Quick Action

## How to Run
1. Open an Opportunity
2. Click "Create Invoice"
3. Add line items
4. Click Save
5. PDF will be generated and downloaded

## Notes
- Built using LWC + Apex
- Uses Visualforce for PDF generation
