public class YahooFinanceAPI {
    // Map des principaux marchés avec leurs suffixes Yahoo Finance
    private static final Map<String, String> MARKET_SUFFIXES = new Map<String, String> {
        'PARIS' => '.PA',
        'EURONEXT PARIS' => '.PA',
        'FRANCE' => '.PA',
        'SBF' => '.PA',    // SBF indique généralement une action française
        'CAC' => '.PA',    // CAC indique généralement une action française
        'LONDON' => '.L',
        'LSE' => '.L',
        'FRANKFURT' => '.F',
        'XETRA' => '.DE',
        'BERLIN' => '.BE',
        'AMSTERDAM' => '.AS',
        'EURONEXT AMSTERDAM' => '.AS',
        'BRUSSELS' => '.BR',
        'EURONEXT BRUSSELS' => '.BR',
        'MILAN' => '.MI',
        'BORSA ITALIANA' => '.MI',
        'MADRID' => '.MC',
        'BME' => '.MC',
        'TORONTO' => '.TO',
        'TSX' => '.TO',
        'ZURICH' => '.SW',
        'SIX' => '.SW',
        'STOCKHOLM' => '.ST',
        'OSLO' => '.OL',
        'COPENHAGEN' => '.CO',
        'HELSINKI' => '.HE',
        'TOKYO' => '.T',
        'HONG KONG' => '.HK',
        'AUSTRALIA' => '.AX',
        'ASX' => '.AX',
        'SYDNEY' => '.AX',
        'SINGAPORE' => '.SI',
        'SAO PAULO' => '.SA',
        'BOVESPA' => '.SA',
        'MEXICO' => '.MX'
    };
    
    // Liste des préfixes pour les indices
    private static final List<String> INDEX_MARKERS = new List<String>{
        'INDEX', 'INDICE', 'INDICE', '^'
    };
    
    public static Map<String, Object> getCompanyDetails(String ticker) {
        if (String.isBlank(ticker)) {
            System.debug('Ticker vide ou null');
            return null;
        }
        
        String originalTicker = ticker;
        
        try {
            // Traitement pour les indices
            for (String marker : INDEX_MARKERS) {
                if (ticker.toUpperCase().contains(marker)) {
                    String indexSymbol = '^' + ticker.replace(' ', '').replace(marker, '');
                    Map<String, Object> result = searchYahooFinance(indexSymbol);
                    if (result != null) return result;
                    break;
                }
            }
            
            // Extraction du ticker et du marché
            List<String> parts = ticker.split(' ');
            String potentialTicker = parts[0];
            String potentialMarket = '';
            
            // Construire le marché potentiel à partir des autres éléments
            if (parts.size() > 1) {
                List<String> marketParts = new List<String>();
                for (Integer i = 1; i < parts.size(); i++) {
                    marketParts.add(parts[i]);
                }
                potentialMarket = String.join(marketParts, ' ').toUpperCase();
            }
            
            // Recherche directe avec le suffixe de marché approprié
            if (String.isNotBlank(potentialMarket)) {
                for (String market : MARKET_SUFFIXES.keySet()) {
                    if (potentialMarket.contains(market) || market.contains(potentialMarket)) {
                        String tickerWithSuffix = potentialTicker + MARKET_SUFFIXES.get(market);
                        System.debug('Essai direct avec suffixe de marché: ' + tickerWithSuffix);
                        Map<String, Object> result = searchYahooFinance(tickerWithSuffix);
                        if (result != null) return result;
                    }
                }
            }
            
            // Si toujours pas de résultat, essayer le ticker original
            Map<String, Object> result = searchYahooFinance(ticker);
            if (result != null) return result;
            
            // Si toujours rien, essayer juste la première partie sans suffixe
            if (potentialTicker != ticker) {
                result = searchYahooFinance(potentialTicker);
                if (result != null) return result;
            }
            
            // Journaliser l'échec
            createAPITask(originalTicker + ' - Aucun résultat Yahoo Finance', 
                         'Aucun résultat trouvé pour le ticker: ' + originalTicker + '\n'+
                         'Ticker extrait essayé: ' + potentialTicker + '\n' +
                         'Marché potentiel: ' + potentialMarket, 
                         'Normal');
            System.debug('Aucun résultat trouvé pour le ticker: ' + originalTicker);
            return null;
        } catch (Exception ex) {
            // Exception lors du traitement
            createAPITask('Exception Yahoo Finance API', 
                         'Ticker: ' + originalTicker + 
                         '\nMessage d\'erreur: ' + ex.getMessage() + 
                         '\nType d\'erreur: ' + ex.getTypeName() +
                         '\nStack trace: ' + ex.getStackTraceString(), 
                         'High');
            System.debug('Exception dans YahooFinanceAPI: ' + ex.getMessage());
            return null;
        }
    }
    
    // Méthode privée pour effectuer la recherche Yahoo Finance
    private static Map<String, Object> searchYahooFinance(String searchTerm) {
        if (String.isBlank(searchTerm)) return null;
        
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        
        try {
            // Encoder le terme de recherche
            String encodedTerm = EncodingUtil.urlEncode(searchTerm, 'UTF-8');
            
            // Endpoint Yahoo Finance pour la recherche
            String endpoint = 'https://query2.finance.yahoo.com/v1/finance/search?q=' + encodedTerm + '&quotesCount=5&newsCount=0';
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36');
            
            System.debug('Envoi de la requête Yahoo Finance: ' + endpoint);
            
            HttpResponse res = http.send(req);
            System.debug('Statut de la réponse: ' + res.getStatusCode());
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> quotes = (List<Object>) responseData.get('quotes');
                
                if (quotes != null && !quotes.isEmpty()) {
                    // Prendre le premier résultat de la liste "quotes"
                    Map<String, Object> firstQuote = (Map<String, Object>) quotes[0];
                    System.debug('Données trouvées pour ' + searchTerm + ': ' + firstQuote);
                    return firstQuote;
                } else {
                    System.debug('Aucun résultat pour: ' + searchTerm);
                    return null;
                }
            } else {
                System.debug('Échec de la requête Yahoo Finance. Statut: ' + res.getStatusCode() + ', Terme: ' + searchTerm);
                return null;
            }
        } catch (Exception ex) {
            System.debug('Exception dans searchYahooFinance: ' + ex.getMessage() + ' pour le terme: ' + searchTerm);
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