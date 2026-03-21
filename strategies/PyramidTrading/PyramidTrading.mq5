//+------------------------------------------------------------------+
//|                                               PyramidTrading.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Import trading library (used for sending Buy/Sell orders)
#include <Trade/Trade.mqh>
CTrade trade; // Create a trading object

// ====== INPUT ======
// Lot size for each trade
input double LotSize = 0.02;

// Store the price of the last opened order
// Used to calculate the 60 pip distance
double lastOpenPrice = 0;


// ====== FUNCTIONS ======

// Get current market price (BID price for Buy logic)
double GetCurrentPrice() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}


// Calculate distance between two prices in pips
// price1 = current price
// price2 = last open price
double GetDistancePips(double price1, double price2) {
   return (price1 - price2) / _Point / 10;
   /*
      _Point = smallest price unit (e.g. 0.00001)
      divide by 10 = convert to standard pips (e.g. 0.00010 = 1 pip)
   */
}


// ====== MAIN FUNCTION ======
void OnTick() {

   // Get current price on every tick
   double currentPrice = GetCurrentPrice();
   
   
   // ====== OPEN FIRST ORDER ======
   // If there are no open positions
   if(PositionsTotal() == 0) {
      
      // Open a Buy order
      if(trade.Buy(LotSize)) {
         
         // Save the price of this order
         lastOpenPrice = currentPrice;
         
         // Log message
         Print("First Buy Opened");
      }
      
      // Stop further execution for this tick
      return;
   }
   
   
   // ====== CALCULATE DISTANCE ======
   double distance = GetDistancePips(currentPrice, lastOpenPrice);
   
   
   // ====== OPEN NEXT ORDER ======
   // Only open if price has moved UP at least 60 pips
   if(distance >= 60) {
      
      // Open another Buy order
      if(trade.Buy(LotSize)) {
         
         // Update last open price
         lastOpenPrice = currentPrice;
         
         // Log message
         Print("New Buy Opened at 60 pips");
      }
   }
}