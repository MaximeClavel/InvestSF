public class YahooFinanceAPI {
    public static Map<String, Object> getCompanyDetails(String ticker) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        
        // Endpoint Yahoo Finance pour la recherche par ticker
        req.setEndpoint('https://query2.finance.yahoo.com/v1/finance/search?q=' + ticker);
        req.setMethod('GET');
        req.setHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36');
        
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> quotes = (List<Object>) responseData.get('quotes');
            
            if (!quotes.isEmpty()) {
                // Prendre le premier résultat de la liste "quotes"
                Map<String, Object> firstQuote = (Map<String, Object>) quotes[0];
                return firstQuote;
            }
        }
        return null; // Gérer les erreurs
    }
}