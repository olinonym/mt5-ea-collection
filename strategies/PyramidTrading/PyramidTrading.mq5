//+------------------------------------------------------------------+
//|                                               PyramidTrading.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

// Import trading library
#include <Trade/Trade.mqh>
CTrade trade; // Create a trading object

// ====== INPUT ======
// Fixed lot size per trade
input double LotSize = 0.02;

// Store the last price opened price (used for 60 pip logic)
double lastOpenPrice = 0;

// ====== FUNCTIONS ======

// Get current market price (BID price for Buy logic)
double GetCurrentPrice() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}


// Calculate distance between two prices in pips
double GetDistancePips(double price1, double price2) {
   return (price1 - price2) / _Point / 10;
}

// ===== CLOSE ORDER LOGIC =====
void ManageCloseOrder() {
   // Loop through all open positions
   for(int i = PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket)) {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double currentPrice = GetCurrentPrice();
         
         double profitPips = (currentPrice - openPrice) / _Point / 10;
         
         if(profitPips >= 180) {
            if(trade.PositionClose(ticket)) {
               Print("Closed 100% | Ticket: ", ticket);
            }
         }
         else if(profitPips >= 120) {
            double closeLot = volume / 2;
            
            if(closeLot >= 0.01) {
               if(trade.PositionClosePartial(ticket, closeLot)) {
                  Print("Close 50% | Ticket: ", ticket);
               }
            }
         }
      }
   }
}


// ====== MAIN FUNCTION ======
void OnTick() {

   ManageCloseOrder();

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