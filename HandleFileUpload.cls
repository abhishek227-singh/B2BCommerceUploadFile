/**
 * @description       Apex class to validate CSV SKUs against Product2.StockKeepingUnit
 * Runs in user mode with sharing to respect org security
 * @author           Agentforce
 */
public with sharing class HandleFileUpload {
    
    public class RowError {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String sku;
        @AuraEnabled public String reason;
        
        public RowError(Integer rowNumber, String sku, String reason) {
            this.rowNumber = rowNumber;
            this.sku = sku;
            this.reason = reason;
        }
    }
    
    public class ValidationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<RowError> errors;
        @AuraEnabled public String filteredCsv;
        
        public ValidationResult(Boolean success, List<RowError> errors, String filteredCsv) {
            this.success = success;
            this.errors = errors;
            this.filteredCsv = filteredCsv;
        }
    }
    
    /**
     * @description Parses CSV content to extract SKU and quantity information
     * Expects first line headers: SKU,Quantity (case-insensitive, trimming spaces)
     * @param csvContent Full CSV file contents as a single string
     * @return Map of SKU to quantity values
     */
    private static Map<String, Integer> parseCsvSkusAndQuantities(String csvContent) {
        Map<String, Integer> skuQuantities = new Map<String, Integer>();
        
        try {
            if (String.isBlank(csvContent)) {
                return skuQuantities; // Return empty map for empty content
            }
            
            // Normalize line endings
            String normalized = csvContent.replaceAll('\\r\\n', '\n').replaceAll('\\r', '\n');
            List<String> lines = normalized.split('\\n');
            
            // Process data lines starting from index 1 (skip header)
            for (Integer i = 1; i < lines.size(); i++) {
                String line = lines[i].trim();
                if (line == '') continue; // skip blank lines
                
                // Split line by comma
                List<String> cols = line.split(',');
                if (cols.size() < 2) {
                    // Skip invalid lines - they will be caught by validation later
                    continue;
                }
                
                String sku = cols[0] != null ? cols[0].trim() : null;
                String quantityStr = cols[1] != null ? cols[1].trim() : null;
                
                // Only process if SKU is not blank and quantity is not blank
                if (!String.isBlank(sku) && !String.isBlank(quantityStr)) {
                    // Validate quantity is numeric
                        Integer quantity = Integer.valueOf(quantityStr);
                        if (quantity > 0) {
                            // Store SKU and quantity (trimmed for consistency)
                            skuQuantities.put(sku.trim(), quantity);
                        }
                }
            }
        } catch (Exception ex) {
            // Silently ignore parsing errors - they will be handled by validation logic
        }
        return skuQuantities;
    }
    
    /**
     * @description Validates CSV content for SKU existence in Product2
     * Expects first line headers: SKU,Quantity (case-insensitive, trimming spaces)
     * @param csvContent Full CSV file contents as a single string
     * @return ValidationResult structured response with success flag and row errors
     */
    @AuraEnabled(cacheable=false)
    public static ValidationResult validateCsvSkus(String csvContent) {
        List<RowError> rowErrors = new List<RowError>();
        
        try {
            if (String.isBlank(csvContent)) {
                rowErrors.add(new RowError(null, null, 'Empty file'));
                return new ValidationResult(false, rowErrors, null);
            }
            
            // Parse CSV to get SKU and quantity mappings
            Map<String, Integer> skuQuantities = parseCsvSkusAndQuantities(csvContent);
            
            // If no valid SKUs found, return error
            if (skuQuantities.isEmpty()) {
                rowErrors.add(new RowError(null, null, 'No valid SKU entries found'));
                return new ValidationResult(false, rowErrors, null);
            }

             Map<String, Id> skuToProduct = new Map<String, Id>();
             skuToProduct = getProductId(skuQuantities);
            
            // Validate each SKU against the query results
            // We need to re-parse the CSV to get row numbers for error reporting
            String normalized = csvContent.replaceAll('\\r\\n', '\n').replaceAll('\\r', '\n');
            List<String> lines = normalized.split('\\n');
            
            // Build filtered CSV content by keeping only valid rows
            List<String> filteredLines = new List<String>();
            // Add header line
            if (lines.size() > 0) {
                filteredLines.add(lines[0]); // Header line
            }
            
            for (Integer i = 1; i < lines.size(); i++) {
                String line = lines[i].trim();
                if (line == '') continue; // skip blank lines
                
                // Split line by comma
                List<String> cols = line.split(',');
                if (cols.size() < 2) {
                    // Invalid number of fields - add error for this row
                    rowErrors.add(new RowError(i + 1, null, 'Invalid number of fields'));
                    continue;
                }
                
                String sku = cols[0] != null ? cols[0].trim() : null;
                
                // Only validate if SKU is not blank
                if (!String.isBlank(sku)) {
                    // Normalize SKU for lookup - same as in query
                    String skuKey = sku.trim().toLowerCase();
                    
                    if (!skuToProduct.containsKey(skuKey)) {
                        rowErrors.add(new RowError(i + 1, sku, 'SKU not found in SF'));
                    } else {
                        // Valid row - add to filtered CSV
                        filteredLines.add(line);
                    }
                } else {
                    // Blank SKU - add to filtered CSV (but we'll still report the error)
                    filteredLines.add(line);
                }
            }
            
            // Create filtered CSV content
            String filteredCsv = String.join(filteredLines, '\n');
            
            Boolean success = rowErrors.isEmpty();
            return new ValidationResult(success, rowErrors, filteredCsv);
            
        } catch (Exception ex) {
            rowErrors.add(new RowError(null, null, 'Unexpected error: ' + ex.getMessage()));
            return new ValidationResult(false, rowErrors, null);
        }
    }

    public static Map<String, Id> getProductId(Map<String,Integer> skuQuantities)
    {
            Set<String> skusForQuery = new Set<String>(skuQuantities.keySet());
            // Query matching Product2 by StockKeepingUnit in USER MODE
            Map<String, Id> skuToProduct = new Map<String, Id>();
            if (!skusForQuery.isEmpty()) {
                for (Product2 p : [
                    SELECT Id, StockKeepingUnit
                    FROM Product2
                    WHERE StockKeepingUnit IN :skusForQuery
                ]) {
                    // Normalize key to lower-case for consistent comparison
                    if (p.StockKeepingUnit != null) {
                        skuToProduct.put(p.StockKeepingUnit.trim().toLowerCase(), p.Id);
                    }
                }
            }
            return skuToProduct;
    }
    
    /**
     * @description Adds items from CSV to B2B Commerce Cart
     * @param cartId The ID of the cart to add items to
     * @param csvContent Full CSV file contents as a single string
     * @return List of RowError objects for any issues encountered
     */
    @AuraEnabled(cacheable=false)
    public static ValidationResult addItemsToCart(String cartId, String csvContent) {
        List<RowError> rowErrors = new List<RowError>();
        String storeName = 'B2B Store';
        Map<String, Integer> skuQuantities = parseCsvSkusAndQuantities(csvContent);
        list<string> unavailablesku = getInventory(skuQuantities);
        if(unavailablesku.size()>0)
        {
            for(String sku : unavailablesku)
            {
                skuQuantities.remove(sku);
                rowErrors.add(new RowError(null, sku, 'Inventory not available'));
            }
        }
        Map<String, Id> skuToProduct = new Map<String, Id>();
        String webstore;
        String account;
        skuToProduct = getProductId(skuQuantities);
        WebCart currentcart = [Select Id,AccountId,WebStoreId from webcart where id =: cartId limit 1];
        if(currentcart!=null)
        {
             webstore = currentcart.WebStoreId;
             account = currentcart.AccountId;
        }
        else{
            ConnectApi.CartInput cartinput = new ConnectApi.CartInput();
            cartinput.name = 'New Cart';
            Webstore store = [Select id from Webstore where name =: storeName limit 1];
            ConnectApi.CartSummary cartoutput = createNewCart(store.id,cartinput);
            cartId = cartoutput.cartId;
        }

        // Process items in chunks of 100 to handle governor limits
        List<ConnectApi.BatchInput> cartitem = new List<ConnectApi.BatchInput>();
        List<ConnectApi.BatchResult> allResults = new List<ConnectApi.BatchResult>();
        Integer batchSize = 100;
        Integer totalItems = skuQuantities.size();
        
        // If we have more than 100 items, process them in batches
        if (totalItems > batchSize) {
            Integer currentIndex = 0;
            List<String> skuKeys = new List<String>(skuQuantities.keySet());
            
            while (currentIndex < totalItems) {
                // Create a chunk of up to 100 items
                List<String> chunkKeys = new List<String>();
                Integer endIndex;
                for (Integer i = currentIndex; i < Math.min(currentIndex + batchSize, totalItems); i++)
                {
                     endIndex = Math.min(currentIndex + batchSize, totalItems);
                }
                for (Integer i = currentIndex; i <= endIndex && i < skuKeys.size(); i++) 
                {
                        chunkKeys.add(skuKeys.get(i));
                }
                
                // Build the cart items for this chunk
                cartitem.clear(); // Clear previous batch items
                for(String sku : chunkKeys){
                    ConnectApi.CartItemInput item = new ConnectApi.CartItemInput();  
                    item.quantity = String.valueOf(skuQuantities.get(sku));
                    item.type = ConnectApi.CartItemType.PRODUCT;
                    // Get the correct product ID for this specific SKU
                    if(skuToProduct.containsKey(sku)) {
                        item.productId = skuToProduct.get(sku);
                    }
                    ConnectApi.BatchInput items = new ConnectApi.BatchInput(item);
                    cartitem.add(items);
                }
                
                // Process this batch
                try {
                    ConnectApi.BatchResult[] result = addItems(webstore, account, cartId, cartitem);
                    if (result != null) {
                        allResults.addAll(result);
                    }
                } catch (Exception Ex) {
                    // If there's an error with a batch, add all remaining items to errors
                    for(String sku : chunkKeys) {
                        rowErrors.add(new RowError(null, sku, 'Error processing item: ' + Ex.getMessage()));
                    }
                    // Continue processing other batches if any remain
                }
                
                currentIndex = endIndex;
            }
        } else {
            // Process all items in a single batch (less than 100 items)
            for(String sku : skuQuantities.keySet()){
                ConnectApi.CartItemInput item = new ConnectApi.CartItemInput();  
                item.quantity = String.valueOf(skuQuantities.get(sku));
                item.type = ConnectApi.CartItemType.PRODUCT;
                // Get the correct product ID for this specific SKU
                if(skuToProduct.containsKey(sku)) {
                    item.productId = skuToProduct.get(sku);
                }
                ConnectApi.BatchInput items = new ConnectApi.BatchInput(item);
                cartitem.add(items);
            }
            try {
                ConnectApi.BatchResult[] result = addItems(webstore, account, cartId, cartitem);
                if (result != null) {
                    allResults.addAll(result);
                }
            } catch (Exception Ex) {
                // If there's an error with the single batch, add all items to errors
                for(String sku : skuQuantities.keySet()) {
                    rowErrors.add(new RowError(null, sku, 'Error processing item: ' + Ex.getMessage()));
                }
            }
        }
        
        try 
            {
                // Map BatchResult entries back to the SKU by index (order preserved)
                if (allResults != null && allResults.size() > 0) {
                    Integer i = 0;
                    for (ConnectApi.BatchResult res : allResults) {
                        // Corresponding SKU from the same order of inputs
                        List<String> orderedSkus = new List<String>(skuQuantities.keySet());
                        String failedSku = (i < orderedSkus.size()) ? orderedSkus[i] : null;
                        // Extract error info from BatchResult
                        // Prefer standard getters; fall back to message if only that exists
                        String reason;
                        if (res != null) { 
                            // Some orgs expose message/errorCode on BatchResult
                            String err;
                            try { err = res.getErrorMessage(); } catch (Exception e) { err = null; }
                            String code;
                            try { code = res.getErrorTypeName(); } catch (Exception e) { code = null; }

                            if (!String.isBlank(err)) {
                                reason = err;
                            } else if (!String.isBlank(code)) {
                                reason = code ;
                            } else if (!String.isBlank(code)) {
                                reason = code;
                            } else {
                                reason = 'Unknown error';
                            }
                        } else {
                            reason = 'Null result from API';
                        }
                        // Only record an error row if this entry failed
                        // If BatchResult has a boolean, check it; otherwise infer failure when a message/error is present
                        Boolean isFailure = false;
                        try { isFailure = (res != null && res.isSuccess == false); } catch (Exception e) {
                            isFailure = (res != null && !String.isBlank(reason));
                        }
                        if (isFailure) {
                            rowErrors.add(new RowError(null, failedSku, reason));
                        }
                        i++;
                    }
                }
                // success if no rowErrors
                Boolean overallSuccess = rowErrors.isEmpty();
                return new ValidationResult(overallSuccess, rowErrors, null);
            } // close try block
        catch (Exception Ex) {
            rowErrors.add(new RowError(null, null, 'Unexpected error: ' + Ex.getMessage()));
            return new ValidationResult(false, rowErrors, null);
        }
        
    }

    public static ConnectApi.BatchResult[] addItems(String webstoreId, String effectiveAccountId, String activeCartOrId, List<ConnectApi.BatchInput> cartItems)
    {
                ConnectApi.BatchResult[] result =  ConnectApi.CommerceCart.addItemsToCart(webstoreId, effectiveAccountId, activeCartOrId, cartItems);
                return result;
        
    }
    public static ConnectApi.CartSummary createNewCart(String webstoreId, ConnectApi.CartInput cartInput)
    {
        ConnectApi.CartSummary NewCart = ConnectApi.CommerceCart.createCart(webstoreId,cartInput);
        return NewCart;
    }

    public static list<string> getInventory(Map<String, Integer> skuQuantities)
    {
        set<String> skus = skuQuantities.keySet();
        List<String> lSku = new List<String>(skus);
        ConnectApi.OCIGetInventoryAvailabilityInputRepresentation input = new ConnectApi.OCIGetInventoryAvailabilityInputRepresentation();
        list<String> locations = new list<String>{'B2BStore_Warehouse'};
        list<string> unavailablesku = new list<string>();
        input.stockKeepingUnits = lSku;
        input.locationIdentifiers = locations;
        ConnectApi.OCIGetInventoryAvailabilityOutputRepresentation result = ConnectApi.OmnichannelInventoryService.getInventoryAvailability(input);
        List<ConnectApi.OCILocationAvailabilityOutputRepresentation> locAvailability = new List<ConnectApi.OCILocationAvailabilityOutputRepresentation>();
        List<ConnectApi.OCIInventoryRecordOutputRepresentation> invList = new list<ConnectApi.OCIInventoryRecordOutputRepresentation>();
        locAvailability = result.locations ;
        for(ConnectApi.OCILocationAvailabilityOutputRepresentation loc : locAvailability) {
            invList.addAll(loc.inventoryRecords);
        }
        Map<String,Integer> invStatus = new Map<String,Integer>();
        for(ConnectApi.OCIInventoryRecordOutputRepresentation inv : invList)
        {
            Integer qty = Integer.valueOf(inv.availableToFulfill);
            invStatus.put(inv.stockKeepingUnit,qty);
        }
        for(String sku:skuQuantities.keySet())
        {
            if(invStatus.containsKey(sku))
            {
                Integer availableQty = invStatus.get(sku);
                Integer requestedQty = skuQuantities.get(sku);
                if(availableQty < requestedQty)
                {
                    unavailablesku.add(sku);
                }
            }
        }
        return unavailablesku;
    }
    
}
