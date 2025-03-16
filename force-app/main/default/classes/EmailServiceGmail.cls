public with sharing class EmailServiceGmail implements Messaging.InboundEmailHandler {
    
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        
        try {
            // Vérifier si le sujet est null
            if (email.subject == null) {
                System.debug('Email reçu avec sujet null - traitement ignoré');
                result.success = true;
                return result;
            }
            
            System.debug('MCLA Email email : ' + email.plainTextBody);
            System.debug('MCLA Email email : ' + email.htmlBody);
            System.debug('MCLA Original subject: ' + email.subject);
            
            //EmailMessage emailMsg = new EmailMessage();
            
            //emailMsg.Subject = email.subject;
            //emailMsg.Status = '3';
            //emailMsg.RelatedToId ='a02gL0000008UaPQAU';
            //emailMsg.HtmlBody = email.htmlBody;
                
            //insert emailMsg;
            
            // Nettoyer le sujet en retirant tous les préfixes de transfert ou réponse
            String cleanSubject = email.subject;
            Pattern prefixPattern = Pattern.compile('(?i)^(?:(?:Re|Fwd|Fw|Forward):\\s*)+');
            Matcher prefixMatcher = prefixPattern.matcher(cleanSubject);
            if (prefixMatcher.find()) {
                cleanSubject = cleanSubject.substring(prefixMatcher.end());
            }
            System.debug('MCLA Cleaned subject: ' + cleanSubject);
            
            // Regex pour extraire les données du sujet (ex: "BOUGHT 1 NKE @ 81.1 (UXXX43662)")
            // Modifié pour accepter les tickers avec espaces
            Pattern pattern = Pattern.compile('^\\s*(BOUGHT|SOLD)\\s+(\\d+)\\s+([A-Z][A-Z0-9\\s]*)\\s+@\\s+([\\d.]+)\\s*\\(([^)]+)\\)');
            Matcher matcher = pattern.matcher(cleanSubject);
            System.debug('MCLA pattern : ' + pattern);
            System.debug('MCLA matcher : ' + matcher);

            System.debug('MCLA matcher.matches() : ' + matcher.matches());
            
            if (matcher.matches()) {
                String transactionType = matcher.group(1).equalsIgnoreCase('BOUGHT') ? 'Buy' : 'Sell';
                Decimal quantity = Decimal.valueOf(matcher.group(2));
                String ticker = matcher.group(3);
                Decimal price = Decimal.valueOf(matcher.group(4));
                String portfolioNumber = matcher.group(5); // Numéro de portefeuille
                
                System.debug('MCLA transactionType : ' + transactionType);
                System.debug('MCLA quantity : ' + quantity);
                System.debug('MCLA ticker : ' + ticker);
                System.debug('MCLA price : ' + price);
                System.debug('MCLA portfolioNumber : ' + portfolioNumber);

                // Gérer les exceptions potentielles lors de l'appel à l'API Yahoo Finance
                // IMPORTANT: L'appel API est fait AVANT le savepoint
                Map<String, Object> companyDetails;
                try {
                    companyDetails = YahooFinanceAPI.getCompanyDetails(ticker);
                } catch (Exception apiEx) {
                    System.debug('Erreur lors de l\'appel à Yahoo Finance API: ' + apiEx.getMessage());
                    companyDetails = null;
                }
                
                // Création d'un point de sauvegarde APRÈS l'appel API pour pouvoir faire un rollback si nécessaire
                Savepoint sp = Database.setSavepoint();
                
                try {
                    // Créer ou mettre à jour le Compte (Account)
                    Account acc;
                    String companyName;
                    if (companyDetails != null) {
                        companyName = getTruncatedCompanyName(companyDetails); // Appel de la méthode de troncature
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
                        companyName = 'Unknown';
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
                            Portfolio__c = portfolio.Id,
                            Name = ticker + ' (' + companyName + ')'
                        );
                        insert position;
                    } else {
                        position = existingPositions[0];
                    }
                    
                    // Essayer d'extraire la date du corps de l'email si disponible
                    Date transactionDate = Date.today();
                    if (email.plainTextBody != null) {
                        // Recherche de la ligne contenant "Sent Date:" dans le corps du message
                        Pattern datePattern = Pattern.compile('Sent Date:\\s*([\\d.-]+)');
                        Matcher dateMatcher = datePattern.matcher(email.plainTextBody);
                        if (dateMatcher.find()) {
                            String dateStr = dateMatcher.group(1).replace('.', '-');
                            try {
                                transactionDate = Date.valueOf(dateStr);
                            } catch (Exception e) {
                                System.debug('Erreur de conversion de date: ' + e.getMessage());
                            }
                        }
                    }
                    
                    Transaction__c myTransc = new Transaction__c(
                        TransactionType__c = transactionType,
                        Quantity__c = quantity,
                        PricePerUnit__c = price,
                        Position__c = position.Id,
                        Enterprise__c = acc.Id,
                        TransactionDate__c = transactionDate
                    );
                    insert myTransc;
                    
                    result.success = true;
                } catch (Exception dmlEx) {
                    // Rollback de toutes les opérations DML en cas d'erreur
                    Database.rollback(sp);
                    throw dmlEx; // Relancer l'exception pour être traitée par le bloc catch externe
                }
            } else {
                // Création d'une tâche pour expliquer pourquoi le matcher est à false
                Task matcherFailTask = new Task(
                    Subject = 'Format d\'email non reconnu',
                    Description = '**Sujet original** : ' + email.subject + 
                                 '\n\n**Sujet nettoyé** : ' + cleanSubject + 
                                 '\n\n**Pattern attendu** : ' + pattern.toString() + 
                                 '\n\n**Raison possible** : Le format du sujet ne correspond pas au pattern attendu.' +
                                 '\n\n**Conseils** : ' +
                                 '\n- Vérifier le format du ticker (peut contenir des espaces ou caractères spéciaux)' +
                                 '\n- Vérifier le format du prix (entier ou décimal)' +
                                 '\n- Vérifier la présence d\'espaces supplémentaires' +
                                 '\n\n**Format attendu** : "BOUGHT/SOLD [quantité] [ticker] @ [prix] ([portefeuille])"',
                    Priority = 'Normal',
                    Status = 'Not Started',
                    OwnerId = UserInfo.getUserId()
                );
                
                try {
                    insert matcherFailTask;
                    System.debug('Tâche créée pour l\'email non reconnu: ' + email.subject);
                } catch (Exception taskEx) {
                    System.debug('Échec de la création de la tâche explicative: ' + taskEx.getMessage());
                }
                
                result.success = true; // Le format ne correspond pas, mais ce n'est pas une erreur
            }
        }
        catch (Exception ex)
        {
            // Créer une Tâche avec les détails de l'erreur
            Task errorTask = new Task(
                Subject = 'Erreur dans le traitement : ' + ex.getTypeName(),
                Description = '**Message d\'erreur** : ' + ex.getMessage() + 
                             '\n\n**Stack Trace** :\n' + ex.getStackTraceString() + 
                             '\n\n**Type d\'erreur** : ' + ex.getTypeName() +
                             '\n\n**Sujet de l\'email** : ' + (email.subject != null ? email.subject : 'null'),
                Priority = 'High',
                Status = 'Not Started',
                OwnerId = UserInfo.getUserId() // Utiliser l'ID de l'utilisateur actuel au lieu d'un ID codé en dur
            );
        
            try {
                insert errorTask; // Enregistrer la tâche
            } catch (Exception taskEx) {
                System.debug('Échec de la création de la tâche : ' + taskEx.getMessage());
            }
            
            // Marquer comme échoué
            result.success = false;
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