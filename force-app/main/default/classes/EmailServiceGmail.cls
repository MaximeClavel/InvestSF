public with sharing class EmailServiceGmail implements Messaging.InboundEmailHandler {
	  
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        
        try {
            
            system.debug('MCLA Email email : ' + email.plainTextBody);
            system.debug('MCLA Email email : ' + email.htmlBody);
            
            //EmailMessage emailMsg = new EmailMessage();
            
            //emailMsg.Subject = email.subject;
            //emailMsg.Status = '3';
            //emailMsg.RelatedToId ='a02gL0000008UaPQAU';
            //emailMsg.HtmlBody = email.htmlBody;
                
            //insert emailMsg;
            
            // Regex pour extraire les données du sujet (ex: "BOUGHT 1 NKE @ 81.1 (UXXX43662)")
            Pattern pattern = Pattern.compile('^(BOUGHT|SOLD)\\s+(\\d+)\\s+([A-Z]+)\\s+@\\s+([\\d.]+)\\s*\\(([^)]+)\\)');
        	Matcher matcher = pattern.matcher(email.subject);
            
            if (matcher.matches()) {
                String transactionType = matcher.group(1).equalsIgnoreCase('BOUGHT') ? 'Buy' : 'Sell';
                Decimal quantity = Decimal.valueOf(matcher.group(2));
                String ticker = matcher.group(3);
                Decimal price = Decimal.valueOf(matcher.group(4));
                String portfolioNumber = matcher.group(5); // Numéro de portefeuille
                
                // Appeler Yahoo Finance pour obtenir les détails de l'entreprise
                Map<String, Object> companyDetails = YahooFinanceAPI.getCompanyDetails(ticker);
                
                // Créer ou mettre à jour le Compte (Account)
                Account acc;
                if (companyDetails != null) {
                    String companyName = getTruncatedCompanyName(companyDetails); // Appel de la méthode de troncature
                    String industry = (String) companyDetails.get('industry');
                    String exchange = (String) companyDetails.get('exchDisp');
                    
                    // Vérifier si le compte existe déjà
                    List<Account> existingAccounts = [SELECT Id FROM Account WHERE TickerSymbol = :ticker LIMIT 1];
                    if (existingAccounts.isEmpty()) {
                        acc = new Account(
                            Name = companyName,
                            TickerSymbol = ticker,
                            Industry = industry,
                            StockExchange__c = exchange,
                            Description = 'Automatically created from IBKR email'
                        );
                        insert acc;
                    } else {
                        acc = existingAccounts[0];
                    }
                } else {
                    // Créer un compte par défaut si Yahoo ne trouve pas le ticker
                    acc = new Account(Name = ticker + ' (Unknown)', TickerSymbol = ticker);
                    insert acc;
                }
                
                // Trouver ou créer le Portefeuille
                List<Portfolio__c> portfolios = [SELECT Id FROM Portfolio__c WHERE PortfolioNumber__c = :portfolioNumber LIMIT 1];
                Portfolio__c portfolio;
                if (portfolios.isEmpty()) {
                    portfolio = new Portfolio__c(
                        PortfolioNumber__c = portfolioNumber,
                        Name = 'IBKR - ' + portfolioNumber // Type par défaut
                    );
                    insert portfolio;
                } else {
                    portfolio = portfolios[0];
                }
                
                // Créer la Position
                Position__c position;
                List<Position__c> existingPositions = [SELECT Id FROM Position__c 
                                                       WHERE TickerSymbol__c = :ticker AND 
                                                       Enterprise__c = :acc.Id AND 
                                                       Portfolio__c = :portfolio.Id LIMIT 1];
                if (existingPositions.isEmpty()) {
                    position = new Position__c(
                        TickerSymbol__c = ticker,
                        Enterprise__c = acc.Id,
                        Portfolio__c = portfolio.Id
                    );
                    insert position;
                } else {
                    position = existingPositions[0];
                }
                
                Transaction__c myTransc = new Transaction__c(
                    TransactionType__c = transactionType,
                    Quantity__c = quantity,
                    PricePerUnit__c = price,
                    Position__c = position.Id,
                    Enterprise__c = acc.Id
                );
                insert myTransc;
            }
            
            result.success = true;
    	}
        catch (Exception ex)
        {
            // Créer une Tâche avec les détails de l'erreur
            Task errorTask = new Task(
                Subject = 'Erreur dans le traitement : ' + ex.getTypeName(),
                Description = '**Message d\'erreur** : ' + ex.getMessage() + 
                             '\n\n**Stack Trace** :\n' + ex.getStackTraceString() + 
                             '\n\n**Type d\'erreur** : ' + ex.getTypeName(),
                Priority = 'High',
                Status = 'Completed',
                OwnerId = '005gL000000UgY5QAK' // Assigner à moi
            );
        
            try {
                insert errorTask; // Enregistrer la tâche
            } catch (Exception taskEx) {
                System.debug('Échec de la création de la tâche : ' + taskEx.getMessage());
            }
        }
        return result;
    }
    
    public static String getTruncatedCompanyName(Map<String, Object> companyDetails) {
    String longName = (String) companyDetails.get('longname');
    
    // Si "longname" est vide, utiliser "shortname" comme fallback
    if (String.isBlank(longName)) {
        longName = (String) companyDetails.get('shortname');
    }
    
    // Tronquer à 255 caractères si nécessaire
    return (longName != null && longName.length() > 255) ? longName.left(255) : longName;
	}
    
  }