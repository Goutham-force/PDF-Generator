/**
 * InvoiceController.cls
 * Handles Invoice creation, line item saving, and PDF generation.
 * Used by the invoiceGenerator LWC component.
 */
public with sharing class InvoiceController {

    // ─── Data Fetch ──────────────────────────────────────────────────────────

    /**
     * Returns a list of open Opportunities for the dropdown in Step 1.
     */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunities() {
        return [
            SELECT Id, Name, AccountId, Account.Name, Amount, CloseDate, StageName
            FROM Opportunity
            WHERE StageName NOT IN ('Closed Won', 'Closed Lost')
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    /**
     * Returns a single Opportunity with its Account details.
     */
    @AuraEnabled(cacheable=true)
    public static Opportunity getOpportunityById(Id opportunityId) {
        return [
            SELECT Id, Name, AccountId, Account.Name, Account.BillingStreet,
                   Account.BillingCity, Account.BillingState, Account.BillingPostalCode,
                   Account.BillingCountry, Amount, CloseDate, StageName, OwnerId, Owner.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }

    // ─── Save Transaction ────────────────────────────────────────────────────

    /**
     * Saves Invoice header + line items in a single DML transaction.
     * Returns the new Invoice__c Id.
     */
    @AuraEnabled
    public static Id saveInvoice(Invoice__c invoiceHeader, String lineItemsJson) {
    Savepoint sp = Database.setSavepoint();
    try {
        insert invoiceHeader;

        List<Invoice_Line_Item__c> items = new List<Invoice_Line_Item__c>();
        List<Object> rawList = (List<Object>) JSON.deserializeUntyped(lineItemsJson);

        for (Object obj : rawList) {
            Map<String, Object> itemMap = (Map<String, Object>) obj;
            Invoice_Line_Item__c li = new Invoice_Line_Item__c();
            li.Invoice__c     = invoiceHeader.Id;
            li.Description__c = (String)  itemMap.get('description');
            li.Quantity__c    = (Decimal)  itemMap.get('quantity');
            li.Unit_Price__c  = (Decimal)  itemMap.get('unitPrice');
            li.Total_Price__c = (Decimal)  itemMap.get('totalPrice');
            items.add(li);
        }

        insert items;
        return invoiceHeader.Id;

    } catch (Exception e) {
        Database.rollback(sp);
        throw new AuraHandledException('Save failed: ' + e.getMessage());
    }
}

    // ─── PDF Generation ──────────────────────────────────────────────────────

    /**
     * Generates PDF content as a base64-encoded string using a Visualforce page.
     * The VF page (InvoicePDF) renders the invoice data.
     */
    @AuraEnabled
    public static String generateInvoicePDF(Id invoiceId) {
        try {
            PageReference pdfPage = Page.InvoicePDF;
            pdfPage.getParameters().put('id', invoiceId);
            pdfPage.setRedirect(false);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('PDF_CONTENT_TEST');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            return EncodingUtil.base64Encode(pdfBlob);
        } catch (Exception e) {
            throw new AuraHandledException('PDF generation failed: ' + e.getMessage());
        }
    }

    /**
     * Saves the PDF as a ContentVersion (File) linked to the Invoice record.
     */
    @AuraEnabled
    public static Id savePDFAsFile(Id invoiceId, String base64Data, String fileName) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title          = fileName;
            cv.PathOnClient   = fileName + '.pdf';
            cv.VersionData    = EncodingUtil.base64Decode(base64Data);
            cv.FirstPublishLocationId = invoiceId;
            insert cv;
            return cv.Id;
        } catch (Exception e) {
            throw new AuraHandledException('File save failed: ' + e.getMessage());
        }
    }

    // ─── Invoice Retrieval (for PDF VF page) ────────────────────────────────

    /**
     * Returns a fully populated Invoice with line items.
     */
    @AuraEnabled(cacheable=true)
    public static InvoiceWrapper getInvoiceDetails(Id invoiceId) {
        Invoice__c inv = [
            SELECT Id, Name, Invoice_Date__c, Due_Date__c, Status__c,
                   Total_Amount__c, Notes__c,
                   Opportunity__c, Opportunity__r.Name,
                   Account__c, Account__r.Name,
                   Account__r.BillingStreet, Account__r.BillingCity,
                   Account__r.BillingState, Account__r.BillingPostalCode,
                   Account__r.BillingCountry
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        List<Invoice_Line_Item__c> items = [
            SELECT Id, Name, Description__c, Quantity__c, Unit_Price__c, Total_Price__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
            ORDER BY CreatedDate ASC
        ];

        InvoiceWrapper wrapper = new InvoiceWrapper();
        wrapper.invoice   = inv;
        wrapper.lineItems = items;
        return wrapper;
    }

    public class InvoiceWrapper {
        @AuraEnabled public Invoice__c invoice;
        @AuraEnabled public List<Invoice_Line_Item__c> lineItems;
    }
}
