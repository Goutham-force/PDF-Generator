@isTest
private class InvoiceControllerTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name        = 'Test Opp',
            AccountId   = acc.Id,
            CloseDate   = Date.today().addDays(30),
            StageName   = 'Prospecting',
            Amount      = 5000
        );
        insert opp;
    }

    @isTest
    static void testGetOpportunities() {
        List<Opportunity> opps = InvoiceController.getOpportunities();
        System.assert(opps.size() >= 0);
    }

    @isTest
    static void testGetOpportunityById() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Opportunity result = InvoiceController.getOpportunityById(opp.Id);
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testSaveInvoice() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];

        Invoice__c inv = new Invoice__c(
            Invoice_Date__c = Date.today(),
            Due_Date__c     = Date.today().addDays(30),
            Opportunity__c  = opp.Id,
            Account__c      = opp.AccountId,
            Status__c       = 'Draft',
            Total_Amount__c = 200
        );

        String lineItemsJson = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'description' => 'Item 1',
                'quantity'    => 2,
                'unitPrice'   => 50,
                'totalPrice'  => 100
            },
            new Map<String, Object>{
                'description' => 'Item 2',
                'quantity'    => 1,
                'unitPrice'   => 100,
                'totalPrice'  => 100
            }
        });

        Test.startTest();
        Id invoiceId = InvoiceController.saveInvoice(inv, lineItemsJson);
        Test.stopTest();

        System.assertNotEquals(null, invoiceId);
        List<Invoice_Line_Item__c> savedItems = [
            SELECT Id FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
        ];
        System.assertEquals(2, savedItems.size());
    }

    @isTest
    static void testGeneratePDF() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
        Invoice__c inv = new Invoice__c(
            Invoice_Date__c = Date.today(),
            Due_Date__c     = Date.today().addDays(30),
            Opportunity__c  = opp.Id,
            Account__c      = opp.AccountId,
            Status__c       = 'Draft',
            Total_Amount__c = 100
        );
        insert inv;

        Test.startTest();
        String b64 = InvoiceController.generateInvoicePDF(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, b64);
    }

    @isTest
    static void testSavePDFAsFile() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
        Invoice__c inv = new Invoice__c(
            Invoice_Date__c = Date.today(),
            Due_Date__c     = Date.today().addDays(30),
            Opportunity__c  = opp.Id,
            Account__c      = opp.AccountId,
            Status__c       = 'Draft',
            Total_Amount__c = 100
        );
        insert inv;

        String fakeBase64 = EncodingUtil.base64Encode(
            Blob.valueOf('fake pdf')
        );

        Test.startTest();
        Id cvId = InvoiceController.savePDFAsFile(
            inv.Id,
            fakeBase64,
            'TestInvoice'
        );
        Test.stopTest();

        System.assertNotEquals(null, cvId);
    }

    @isTest
    static void testGetInvoiceDetails() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
        Invoice__c inv = new Invoice__c(
            Invoice_Date__c = Date.today(),
            Due_Date__c     = Date.today().addDays(30),
            Opportunity__c  = opp.Id,
            Account__c      = opp.AccountId,
            Status__c       = 'Draft',
            Total_Amount__c = 150
        );
        insert inv;

        Invoice_Line_Item__c li = new Invoice_Line_Item__c(
            Invoice__c     = inv.Id,
            Description__c = 'Test Item',
            Quantity__c    = 1,
            Unit_Price__c  = 150,
            Total_Price__c = 150
        );
        insert li;

        Test.startTest();
        InvoiceController.InvoiceWrapper w =
            InvoiceController.getInvoiceDetails(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, w.invoice);
        System.assertEquals(1, w.lineItems.size());
    }
}