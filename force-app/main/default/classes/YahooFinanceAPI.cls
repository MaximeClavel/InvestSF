public class YahooFinanceAPI {
    public static Map<String, Object> getCompanyDetails(String ticker) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        
        try {
            // Encoder le ticker pour gérer les espaces et caractères spéciaux
            String encodedTicker = EncodingUtil.urlEncode(ticker, 'UTF-8');
            
            // Endpoint Yahoo Finance pour la recherche par ticker
            req.setEndpoint('https://query2.finance.yahoo.com/v1/finance/search?q=' + encodedTicker);
            req.setMethod('GET');
            req.setHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36');
            
            System.debug('Envoi de la requête Yahoo Finance pour le ticker: ' + ticker + ' (encodé: ' + encodedTicker + ')');
            
            HttpResponse res = http.send(req);
            System.debug('Statut de la réponse: ' + res.getStatusCode());
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> quotes = (List<Object>) responseData.get('quotes');
                
                if (quotes != null && !quotes.isEmpty()) {
                    // Prendre le premier résultat de la liste "quotes"
                    Map<String, Object> firstQuote = (Map<String, Object>) quotes[0];
                    System.debug('Données trouvées pour ' + ticker + ': ' + firstQuote);
                    return firstQuote;
                } else {
                    // Aucun résultat trouvé pour ce ticker
                    createAPITask(ticker + ' - Aucun résultat Yahoo Finance', 
                                 'Aucun résultat trouvé pour le ticker: ' + ticker + '\n'+'https://query2.finance.yahoo.com/v1/finance/search?q=' + encodedTicker, 
                                 'Normal');
                    System.debug('Aucun résultat trouvé pour le ticker: ' + ticker);
                    return null;
                }
            } else {
                // Problème avec la requête API
                String errorBody = res.getBody() != null ? res.getBody() : 'Corps de réponse vide';
                createAPITask('Erreur de requête Yahoo Finance', 
                             'Statut: ' + res.getStatusCode() + '\nTicker: ' + ticker + 
                             '\nRéponse: ' + errorBody.left(32000), // Limite à 32k caractères
                             'High');
                System.debug('Échec de la requête Yahoo Finance. Statut: ' + res.getStatusCode());
                return null;
            }
        } catch (Exception ex) {
            // Exception lors du traitement
            createAPITask('Exception Yahoo Finance API', 
                         'Ticker: ' + ticker + 
                         '\nMessage d\'erreur: ' + ex.getMessage() + 
                         '\nType d\'erreur: ' + ex.getTypeName() +
                         '\nStack trace: ' + ex.getStackTraceString(), 
                         'High');
            System.debug('Exception dans YahooFinanceAPI: ' + ex.getMessage());
            return null;
        }
    }
    
    // Méthode privée pour créer une tâche
    private static void createAPITask(String subject, String description, String priority) {
        try {
            Task apiTask = new Task(
                Subject = subject,
                Description = description,
                Priority = priority,
                Status = 'Not Started',
                OwnerId = UserInfo.getUserId(),
                ActivityDate = Date.today() // Due date = aujourd'hui
            );
            
            insert apiTask;
            System.debug('Tâche créée: ' + subject);
        } catch (Exception taskEx) {
            System.debug('Échec de création de la tâche: ' + taskEx.getMessage());
        }
    }
}