import { LightningElement, track, wire, api } from 'lwc';
import { NavigationMixin }                    from 'lightning/navigation';
import { ShowToastEvent }                     from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue }           from 'lightning/uiRecordApi';

// Apex methods
import getOpportunities    from '@salesforce/apex/InvoiceController.getOpportunities';
import getOpportunityById  from '@salesforce/apex/InvoiceController.getOpportunityById';
import saveInvoice         from '@salesforce/apex/InvoiceController.saveInvoice';
import generateInvoicePDF  from '@salesforce/apex/InvoiceController.generateInvoicePDF';
import savePDFAsFile       from '@salesforce/apex/InvoiceController.savePDFAsFile';

// Opportunity fields (used when launched as a Quick Action on Opportunity)
import OPPORTUNITY_NAME  from '@salesforce/schema/Opportunity.Name';
import ACCOUNT_ID        from '@salesforce/schema/Opportunity.AccountId';
import ACCOUNT_NAME      from '@salesforce/schema/Opportunity.Account.Name';
import AMOUNT_FIELD      from '@salesforce/schema/Opportunity.Amount';
import CLOSE_DATE_FIELD  from '@salesforce/schema/Opportunity.CloseDate';
import STAGE_FIELD       from '@salesforce/schema/Opportunity.StageName';

const FIELDS = [OPPORTUNITY_NAME, ACCOUNT_ID, ACCOUNT_NAME, AMOUNT_FIELD, CLOSE_DATE_FIELD, STAGE_FIELD];

const today = () => new Date().toISOString().substring(0, 10);
const addDays = (dateStr, n) => {
    const d = new Date(dateStr);
    d.setDate(d.getDate() + n);
    return d.toISOString().substring(0, 10);
};
let _keyCounter = 0;
const newKey = () => `li_${++_keyCounter}`;

export default class InvoiceGenerator extends NavigationMixin(LightningElement) {

    @api recordId;

    // ── Wire: load the Opportunity record when launched from Quick Action ─────
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredOpportunity({ data, error }) {
        if (data) {
            this._prefillFromWire(data);
        }
    }

    _prefillFromWire(data) {
        const id = this.recordId;
        if (!id) return;
        this.selectedOpportunityId = id;
        this.selectedOpportunity = {
            Id:        id,
            Name:      getFieldValue(data, OPPORTUNITY_NAME),
            AccountId: getFieldValue(data, ACCOUNT_ID),
            Account: { Name: getFieldValue(data, ACCOUNT_NAME) },
            Amount:    getFieldValue(data, AMOUNT_FIELD),
            CloseDate: getFieldValue(data, CLOSE_DATE_FIELD),
            StageName: getFieldValue(data, STAGE_FIELD)
        };
    }

    @track currentStep = '1';

    get isStep1() { return this.currentStep === '1' && !this.isSaved; }
    get isStep2() { return this.currentStep === '2' && !this.isSaved; }
    get isStep3() { return this.currentStep === '3' && !this.isSaved; }

    @track isLoading  = false;
    @track errorMessage;

    clearError() { this.errorMessage = null; }

    _setError(msg) {
        this.errorMessage = msg;
        this.isLoading    = false;
    }

    @track opportunityList     = [];
    @track selectedOpportunityId;
    @track selectedOpportunity;
    @track invoiceDate   = today();
    @track dueDate       = addDays(today(), 30);
    @track invoiceStatus = 'Draft';

    connectedCallback() {
        this._loadOpportunities();
    }

    async _loadOpportunities() {
        try {
            this.opportunityList = await getOpportunities();
        } catch (e) {
            this._setError('Failed to load opportunities: ' + (e.body?.message || e.message));
        }
    }

    get opportunityOptions() {
        return this.opportunityList.map(o => ({
            label: `${o.Name} – ${o.Account?.Name || ''}`,
            value: o.Id
        }));
    }

    get statusOptions() {
        return [
            { label: 'Draft',   value: 'Draft'   },
            { label: 'Sent',    value: 'Sent'     },
            { label: 'Paid',    value: 'Paid'     },
            { label: 'Overdue', value: 'Overdue'  }
        ];
    }

    get selectedOpportunityAmount() {
        if (!this.selectedOpportunity?.Amount) return '—';
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD'
        }).format(this.selectedOpportunity.Amount);
    }

    async handleOpportunityChange(evt) {
        this.selectedOpportunityId = evt.detail.value;
        try {
            this.isLoading = true;
            this.selectedOpportunity = await getOpportunityById({ opportunityId: this.selectedOpportunityId });
        } catch (e) {
            this._setError('Error loading opportunity: ' + (e.body?.message || e.message));
        } finally {
            this.isLoading = false;
        }
    }

    handleInvoiceDateChange(evt) { this.invoiceDate   = evt.detail.value; }
    handleDueDateChange(evt)     { this.dueDate       = evt.detail.value; }
    handleStatusChange(evt)      { this.invoiceStatus = evt.detail.value; }

    goToStep2() {
        if (!this._validateStep1()) return;
        this.currentStep = '2';
        if (this.lineItems.length === 0) this.addLineItem();
    }

    _validateStep1() {
        if (!this.selectedOpportunityId) {
            this._setError('Please select an Opportunity.');
            return false;
        }
        if (!this.invoiceDate) {
            this._setError('Please enter an Invoice Date.');
            return false;
        }
        if (!this.dueDate) {
            this._setError('Please enter a Due Date.');
            return false;
        }
        if (new Date(this.dueDate) < new Date(this.invoiceDate)) {
            this._setError('Due Date cannot be before Invoice Date.');
            return false;
        }
        this.errorMessage = null;
        return true;
    }

    @track lineItems  = [];
    @track invoiceNotes = '';

    get hasLineItems() { return this.lineItems.length > 0; }

    get invoiceTotal() {
        return this.lineItems.reduce((sum, item) => sum + (item.totalPrice || 0), 0);
    }

    addLineItem() {
        const key = newKey();
        this.lineItems = [
            ...this.lineItems,
            {
                key,
                displayIndex : this.lineItems.length + 1,
                description  : '',
                quantity     : 1,
                unitPrice    : 0,
                totalPrice   : 0
            }
        ];
    }

    removeLineItem(evt) {
        const key = evt.currentTarget.dataset.id;
        this.lineItems = this.lineItems
            .filter(i => i.key !== key)
            .map((i, idx) => ({ ...i, displayIndex: idx + 1 }));
    }

    handleLineItemChange(evt) {
        const key   = evt.target.dataset.id;
        const field = evt.target.dataset.field;
        const val   = evt.detail.value;

        this.lineItems = this.lineItems.map(item => {
            if (item.key !== key) return item;
            const updated = { ...item, [field]: val };
            const qty   = parseFloat(updated.quantity)  || 0;
            const price = parseFloat(updated.unitPrice)  || 0;
            updated.totalPrice = parseFloat((qty * price).toFixed(2));
            return updated;
        });
    }

    handleNotesChange(evt) { this.invoiceNotes = evt.detail.value; }

    goToStep1() { this.currentStep = '1'; this.errorMessage = null; }
    goToStep3() {
        if (!this._validateStep2()) return;
        this.currentStep = '3';
        this.errorMessage = null;
    }

    _validateStep2() {
        if (this.lineItems.length === 0) {
            this._setError('Please add at least one line item.');
            return false;
        }
        for (const item of this.lineItems) {
            if (!item.description?.trim()) {
                this._setError(`Line item #${item.displayIndex} is missing a description.`);
                return false;
            }
            if (!item.quantity || parseFloat(item.quantity) <= 0) {
                this._setError(`Line item #${item.displayIndex} must have a positive quantity.`);
                return false;
            }
            if (item.unitPrice === null || item.unitPrice === undefined || parseFloat(item.unitPrice) < 0) {
                this._setError(`Line item #${item.displayIndex} must have a non-negative unit price.`);
                return false;
            }
        }
        this.errorMessage = null;
        return true;
    }

    @track isSaved         = false;
    @track savedInvoiceId;
    @track savedInvoiceName;
    @track pdfBase64;

    async saveAndGeneratePDF() {
        this.isLoading    = true;
        this.errorMessage = null;

        try {
           const invoiceHeader = {
    Invoice_Date__c : this.invoiceDate,
    Due_Date__c     : this.dueDate,
    Status__c       : this.invoiceStatus,
    Opportunity__c  : this.selectedOpportunityId,
    Account__c      : this.selectedOpportunity?.AccountId || null,
    Total_Amount__c : this.invoiceTotal,
    Notes__c        : this.invoiceNotes || ''
};

            const apexLineItems = this.lineItems.map(item => ({
                sobjectType    : 'Invoice_Line_Item__c',
                Description__c : item.description,
                Quantity__c    : parseFloat(item.quantity),
                Unit_Price__c  : parseFloat(item.unitPrice),
                Total_Price__c : item.totalPrice
            }));

           const lineItemsJson = JSON.stringify(this.lineItems.map(item => ({
    description : item.description,
    quantity    : parseFloat(item.quantity),
    unitPrice   : parseFloat(item.unitPrice),
    totalPrice  : item.totalPrice
})));

const invoiceId = await saveInvoice({ 
    invoiceHeader, 
    lineItemsJson 
})

            this.pdfBase64 = await generateInvoicePDF({ invoiceId });

            const invoiceName = `Invoice_${this.savedInvoiceName || invoiceId}`;
            await savePDFAsFile({
                invoiceId,
                base64Data : this.pdfBase64,
                fileName   : invoiceName
            });

            this.savedInvoiceName = invoiceId;   
            this.isSaved          = true;

            this.dispatchEvent(new ShowToastEvent({
                title   : 'Success',
                message : 'Invoice created and PDF generated!',
                variant : 'success'
            }));

        } catch (e) {
            this._setError('Error: ' + (e.body?.message || e.message || JSON.stringify(e)));
        } finally {
            this.isLoading = false;
        }
    }

    downloadPDF() {
        if (!this.pdfBase64) {
            this._setError('PDF data is not available.');
            return;
        }
        try {
            const byteCharacters = atob(this.pdfBase64);
            const byteNumbers    = new Uint8Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
                byteNumbers[i] = byteCharacters.charCodeAt(i);
            }
            const blob    = new Blob([byteNumbers], { type: 'application/pdf' });
            const url     = URL.createObjectURL(blob);
            const anchor  = document.createElement('a');
            anchor.href     = url;
            anchor.download = `Invoice_${this.savedInvoiceId}.pdf`;
            document.body.appendChild(anchor);
            anchor.click();
            document.body.removeChild(anchor);
            URL.revokeObjectURL(url);
        } catch (e) {
            this._setError('Download failed: ' + e.message);
        }
    }

    navigateToInvoice() {
        this[NavigationMixin.Navigate]({
            type       : 'standard__recordPage',
            attributes : {
                recordId   : this.savedInvoiceId,
                objectApiName : 'Invoice__c',
                actionName : 'view'
            }
        });
    }
}
