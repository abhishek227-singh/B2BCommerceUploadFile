import { LightningElement, track,wire } from 'lwc';
import validateCsvSkus from '@salesforce/apex/HandleFileUpload.validateCsvSkus';
import addItemsToCart from '@salesforce/apex/HandleFileUpload.addItemsToCart';
import { CartSummaryAdapter } from "commerce/cartApi";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FileUpload extends LightningElement {
    cartId;
    @track errorRows = [];
    @track dataRows = [];
    @track isProcessing = false;
    // Results from addItemsToCart Apex call (ValidationResult)
    @track addItemsResult = null;
    @track columns = [
        { label: 'SKU', fieldName: 'sku', type: 'text', initialWidth: 200 },
        { label: 'Reason', fieldName: 'reason', type: 'text' }
    ];
    @track dataColumns = [
        { label: 'SKU', fieldName: 'sku', type: 'text', initialWidth: 200 },
        { label: 'Quantity', fieldName: 'quantity', type: 'number', initialWidth: 120 }
    ];

    get hasErrors() {
        return this.errorRows && this.errorRows.length > 0;
    }

    get hasDataRows() {
        return this.dataRows && this.dataRows.length > 0;
    }

    // Derived flags for displaying addItemsToCart results
    get hasAddItemsResult() {
        return this.addItemsResult !== null && this.addItemsResult !== undefined;
    }
    get addItemsSucceeded() {
        return this.hasAddItemsResult && this.addItemsResult.success === true;
    }
    get addItemsHasErrors() {
        return this.hasAddItemsResult && Array.isArray(this.addItemsResult.errors) && this.addItemsResult.errors.length > 0;
    }

    @wire(CartSummaryAdapter)
    getCartSummary({ data, error }) {
        if (data) {
            this.cartId = data.cartId;
        }
        else if (error) {
            console.error("Error retrieving cart ID:", error);
        }
    }

    handleFileChange(event) {
        const files = event.target.files;
        if (files.length > 0) {
            const file = files[0];
            
            // Validate file type - only accept CSV files
            if (file.type !== 'text/csv' && !file.name.toLowerCase().endsWith('.csv')) {
                this.errorRows = [{
                    id: '1',
                    sku: '',
                    quantity: null,
                    reason: 'File not supported'
                }];
                this.dataRows = [];
                return;
            }
            
            // Reset previous data and errors
            this.errorRows = [];
            this.dataRows = [];
            this.addItemsResult = null;
            
            // Read file content
            const reader = new FileReader();
            reader.onload = (e) => {
                const content = e.target.result;
                // Set processing flag
                this.isProcessing = true;
                // First, do basic CSV validation (checking for data rows beyond header)
                const basicErrors = this.validateCSVBasic(content);
                
                // If there are basic validation errors, display them and stop
                if (basicErrors.length > 0) {
                    this.errorRows = basicErrors;
                    this.isProcessing = false;
                    return;
                }
                
                // Parse and store data rows for display
                this.parseAndStoreDataRows(content);
                // Call Apex for SKU validation only
                validateCsvSkus({ csvContent: content })
                    .then(result => {
                        // Convert the Apex result to match our expected format
                        if (result.errors && result.errors.length > 0) {
                            // Convert errors to match the expected format
                            const convertedErrors = result.errors.map(error => ({
                                id: error.rowNumber?.toString() || 'unknown',
                                sku: error.sku || '',
                                quantity: null,
                                reason: error.reason || 'Unknown error'
                            }));
                            this.errorRows = convertedErrors;
                            
                            // Even if there are validation errors, still try to add valid items to cart
                            // Use filtered CSV from validateCsvSkus if available
                            if (this.cartId && result.filteredCsv) {
                                addItemsToCart({ cartId: this.cartId, csvContent: result.filteredCsv })
                                    .then(result => {
                                        // result is ValidationResult { success: Boolean, errors: [RowError] }
                                        this.addItemsResult = result;
                                        // also surface any errors into the existing error grid if present
                                        if (result && Array.isArray(result.errors) && result.errors.length > 0) {
                                            const convertedErrors = result.errors.map(error => ({
                                                id: error.rowNumber?.toString() || 'unknown',
                                                sku: error.sku || '',
                                                quantity: null,
                                                reason: error.reason || 'Unknown error'
                                            }));
                                            // Combine validation errors with cart errors
                                            this.errorRows = [...convertedErrors, ...this.errorRows];
                                        }
                                        this.isProcessing = false;
                                        // Show toast message when processing is complete
                                        const toastEvent = new ShowToastEvent({
                                            title: 'File Processing Complete',
                                            message: 'Uploaded file processed successfully.',
                                            variant: 'success'
                                        });
                                        this.dispatchEvent(toastEvent);
                                    })
                                    .catch(error => {
                                        // capture Add-to-cart failure into addItemsResult without adding extra validations
                                        this.addItemsResult = {
                                            success: false,
                                            errors: [{
                                                rowNumber: null,
                                                sku: '',
                                                reason: 'Error adding items to cart: ' + (error?.body?.message || 'Unknown error')
                                            }]
                                        };
                                        // Still show both validation and cart errors
                                        this.errorRows = [...this.errorRows, {
                                            id: '1',
                                            sku: '',
                                            quantity: null,
                                            reason: 'Error adding items to cart: ' + (error?.body?.message || 'Unknown error')
                                        }];
                                        // Show toast message when processing is complete
                                        const toastEvent = new ShowToastEvent({
                                            title: 'File Processing Complete',
                                            message: 'Uploaded file processed successfully.',
                                            variant: 'success'
                                        });
                                        this.dispatchEvent(toastEvent);
                                        this.isProcessing = false;
                                    });
                            } else {
                                // Show toast message when processing is complete (even if no cart items)
                                const toastEvent = new ShowToastEvent({
                                    title: 'File Processing Complete',
                                    message: 'Uploaded file processed successfully.',
                                    variant: 'success'
                                });
                                this.dispatchEvent(toastEvent);
                                this.isProcessing = false;
                            }
                        } else {
                            this.errorRows = [];
                            // If validation passes and we have a cart ID, add items to cart
                            if (this.cartId) {
                                // Use filtered CSV from validateCsvSkus if available
                                const csvToSend = result.filteredCsv ? result.filteredCsv : content;
                                addItemsToCart({ cartId: this.cartId, csvContent: csvToSend })
                                    .then(result => {
                                        // result is ValidationResult { success: Boolean, errors: [RowError] }
                                        this.addItemsResult = result;
                                        // also surface any errors into the existing error grid if present
                                        if (result && Array.isArray(result.errors) && result.errors.length > 0) {
                                            const convertedErrors = result.errors.map(error => ({
                                                id: error.rowNumber?.toString() || 'unknown',
                                                sku: error.sku || '',
                                                quantity: null,
                                                reason: error.reason || 'Unknown error'
                                            }));
                                            this.errorRows = convertedErrors;
                                        }
                                        // Show toast message when processing is complete
                                        const toastEvent = new ShowToastEvent({
                                            title: 'File Processing Complete',
                                            message: 'Uploaded file processed successfully.',
                                            variant: 'success'
                                        });
                                        this.dispatchEvent(toastEvent);
                                        this.isProcessing = false;
                                    })
                                    .catch(error => {
                                        // capture Add-to-cart failure into addItemsResult without adding extra validations
                                        this.addItemsResult = {
                                            success: false,
                                            errors: [{
                                                rowNumber: null,
                                                sku: '',
                                                reason: 'Error adding items to cart: ' + (error?.body?.message || 'Unknown error')
                                            }]
                                        };
                                        this.errorRows = [{
                                            id: '1',
                                            sku: '',
                                            quantity: null,
                                            reason: 'Error adding items to cart: ' + (error?.body?.message || 'Unknown error')
                                        }];
                                        // Show toast message when processing is complete
                                        const toastEvent = new ShowToastEvent({
                                            title: 'File Processing Complete',
                                            message: 'Uploaded file processed successfully.',
                                            variant: 'success'
                                        });
                                        this.dispatchEvent(toastEvent);
                                        this.isProcessing = false;
                                    });
                            } else {
                                // Show toast message when processing is complete (even if no cart items)
                                const toastEvent = new ShowToastEvent({
                                    title: 'File Processing Complete',
                                    message: 'Uploaded file processed successfully.',
                                    variant: 'success'
                                });
                                this.dispatchEvent(toastEvent);
                                this.isProcessing = false;
                            }
                        }
                    })
                    .catch(error => {
                        // Handle any errors from the Apex call
                        this.errorRows = [{
                            id: '1',
                            sku: '',
                            quantity: null,
                            reason: 'Validation error: ' + error.body.message
                        }];
                        // Show toast message when processing is complete (even with errors)
                        const toastEvent = new ShowToastEvent({
                            title: 'File Processing Complete',
                            message: 'Uploaded file processed successfully.',
                            variant: 'success'
                        });
                        this.dispatchEvent(toastEvent);
                        this.isProcessing = false;
                    });
            };
            reader.onerror = () => {
                this.errorRows = [{
                    id: '1',
                    sku: '',
                    quantity: null,
                    reason: 'Failed to read file'
                }];
            };
            reader.readAsText(file);
        }
    }

    parseAndStoreDataRows(content) {
        // Split content into lines
        const lines = content.split(/\r?\n/);
        const dataRows = [];
        // Skip header line (index 0) and process data rows
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line === '') continue; // skip blank lines
            
            const fields = line.split(',');
            if (fields.length >= 2) {
                const sku = fields[0].trim();
                const quantity = fields[1].trim();
                // Convert quantity to integer if it's a valid number
                const quantityValue = /^\d+$/.test(quantity) ? parseInt(quantity, 10) : null;
                
                dataRows.push({
                    id: `${i + 1}`,
                    sku: sku,
                    quantity: quantityValue
                });
            }
        }
        this.dataRows = dataRows;
    }

    validateCSVBasic(content) {
        // Split content into lines
        const lines = content.split(/\r?\n/);
        const errors = [];
        
        // Check if we have at least header line
        if (lines.length < 1) {
            errors.push({
                id: '1',
                sku: '',
                quantity: null,
                reason: 'Empty file'
            });
            return errors;
        }
        
        // Check for empty file (all lines are empty or whitespace)
        const nonEmptyLines = lines.filter(line => line.trim() !== '');
        if (nonEmptyLines.length < 1) {
            errors.push({
                id: '1',
                sku: '',
                quantity: null,
                reason: 'Empty file'
            });
            return errors;
        }
        
        // Validate header (first non-empty line)
        const headerLine = nonEmptyLines[0].trim();
        const headers = headerLine.split(',').map(h => h.trim().toLowerCase());
        
        if (headers.length !== 2 || headers[0] !== 'sku' || headers[1] !== 'quantity') {
            errors.push({
                id: '1',
                sku: '',
                quantity: null,
                reason: 'Invalid header. Expected "SKU,Quantity"'
            });
            return errors;
        }
        
        // Check if we have data rows beyond the header
        // If we only have the header line, there are no data rows
        if (nonEmptyLines.length < 2) {
            errors.push({
                id: '1',
                sku: '',
                quantity: null,
                reason: 'File must contain at least one data row'
            });
            return errors;
        }
        
        // Process data lines (starting from second non-empty line)
        for (let i = 1; i < nonEmptyLines.length; i++) {
            const line = nonEmptyLines[i].trim();
            if (line === '') continue;
            
            const fields = line.split(',');
            if (fields.length !== 2) {
                errors.push({
                    id: `${i + 1}`,
                    sku: '',
                    quantity: null,
                    reason: `Invalid number of fields. Expected 2, got ${fields.length}`
                });
                continue;
            }
            
            const sku = fields[0].trim();
            const quantityStr = fields[1].trim();
            
            // Validate SKU (should be text)
            if (sku === '') {
                errors.push({
                    id: `${i + 1}`,
                    sku: '',
                    quantity: null,
                    reason: 'SKU is required'
                });
                continue;
            }
            
            // Validate Quantity (should be integer)
            if (quantityStr === '') {
                errors.push({
                    id: `${i + 1}`,
                    sku: sku,
                    quantity: null,
                    reason: 'Quantity is required'
                });
                continue;
            }
            
            if (!/^-?\d+$/.test(quantityStr)) {
                errors.push({
                    id: `${i + 1}`,
                    sku: sku,
                    quantity: null,
                    reason: 'Quantity must be an integer'
                });
                continue;
            }
        }
        
        return errors;
    }
}
