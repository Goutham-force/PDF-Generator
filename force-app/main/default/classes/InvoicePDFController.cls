/**
 * InvoicePDFController.cls
 * Apex controller for the InvoicePDF Visualforce page.
 * Fetches invoice + line items based on the 'id' URL parameter.
 */
public with sharing class InvoicePDFController {

    public Invoice__c              invoice   { get; private set; }
    public List<Invoice_Line_Item__c> lineItems { get; private set; }
    public Integer                 rowIndex  { get; set; }

    public InvoicePDFController() {
        String invoiceId = ApexPages.currentPage().getParameters().get('id');
        if (String.isNotBlank(invoiceId)) {
            loadInvoice(invoiceId);
        }
        rowIndex = 0;
    }

    private void loadInvoice(String invoiceId) {
        try {
            invoice = [
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

            lineItems = [
                SELECT Id, Name, Description__c, Quantity__c, Unit_Price__c, Total_Price__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :invoiceId
                ORDER BY CreatedDate ASC
            ];
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Error loading invoice: ' + e.getMessage()
            ));
            invoice   = new Invoice__c();
            lineItems = new List<Invoice_Line_Item__c>();
        }
    }
}
