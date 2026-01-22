# File Upload Component Documentation

## Background

This LWC component and Apex class provide a streamlined solution for B2B Commerce users to quickly add multiple products to their shopping cart using CSV files. Instead of manually adding each product individually, users can prepare a CSV file with SKU and quantity information and upload it to automatically process and add items to their cart.

The component addresses the common business need for efficient bulk product addition in B2B commerce environments where customers often need to order large quantities of various products at once.

## Use Case

This functionality is particularly useful in the following scenarios:

- **Bulk Ordering**: Customers need to order multiple products with specific quantities
- **Recurring Orders**: Regular orders that follow a standard pattern
- **Seasonal Purchasing**: Large volume purchases during peak seasons
- **Inventory Management**: Quick replenishment of stock levels
- **Order Processing**: Efficient handling of large order files from suppliers or internal teams

## How It Works

1. **User Interface**: The component presents a file upload input for CSV files
2. **CSV Validation**: The system validates the CSV format and structure
3. **SKU Verification**: Each SKU in the CSV is validated against existing Product2 records
4. **Inventory Check**: Available inventory is verified before adding items to cart
5. **Cart Integration**: Valid items are added to the user's B2B Commerce cart
6. **Error Reporting**: Both validation and cart processing errors are displayed clearly

## Features

### Frontend (LWC Component)
- CSV file upload with `.csv` extension restriction
- Real-time CSV validation (format, header, required fields)
- Data preview table showing SKU and quantity
- Error display for validation issues
- Processing indicator during operations
- Toast notifications for operation completion
- Integration with B2B Commerce cart API
- Responsive design using Lightning Design System

### Backend (Apex Class)
- Comprehensive CSV parsing and validation
- SKU lookup against Product2 records
- Inventory availability checking
- Batch processing for large datasets (up to 100 items per batch)
- Error handling and structured error reporting
- Integration with Salesforce Commerce Connect API
- Support for user mode security context

## Implementation Details

### Component Structure
- **fileUpload.html**: Lightning Web Component markup with file input and data display
- **fileUpload.js**: Component logic handling file reading, validation, and API calls
- **fileUpload.js-meta.xml**: Component metadata

### Apex Class Structure
- **HandleFileUpload.cls**: Main Apex class with supporting inner classes
- **RowError**: Inner class for error reporting
- **ValidationResult**: Inner class for structured validation results
- **parseCsvSkusAndQuantities**: Private method for CSV parsing
- **validateCsvSkus**: Public method for SKU validation
- **getProductId**: Helper method for Product2 lookup
- **addItemsToCart**: Public method for cart integration
- **getInventory**: Method for inventory availability checking
- **addItems**: Wrapper for Commerce Cart API
- **createNewCart**: Helper for cart creation

### Technical Specifications
- **File Format**: CSV with header "SKU,Quantity" (case insensitive)
- **SKU Validation**: Matches against Product2.StockKeepingUnit field
- **Quantity Validation**: Must be positive integers
- **Batch Processing**: Supports up to 100 items per batch for performance
- **Security**: Runs in user mode with sharing to respect org security
- **Error Handling**: Comprehensive error reporting with row-level details

## Usage Instructions

1. Navigate to the component in the B2B Commerce interface
2. Click the "Upload CSV file" button
3. Select a properly formatted CSV file (SKU,Quantity format)
4. Review the preview table of uploaded data
5. View any validation errors if present
6. Wait for processing to complete
7. Check the cart for successfully added items
8. Review any errors in the error display area

## Limitations

- Only accepts CSV files with specific format (SKU,Quantity header)
- Requires valid Product2 records with matching SKUs
- Limited to B2B Commerce cart integration
- Batch processing limited to 100 items per batch
- Inventory checks only validate against specific warehouse locations
