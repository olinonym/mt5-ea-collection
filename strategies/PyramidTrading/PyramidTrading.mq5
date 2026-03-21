//+------------------------------------------------------------------+
//|                                               PyramidTrading.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Trade/Trade.mqh>
CTrade trade; 

input double LotSize = 0.02;
double lastOpenPrice = 0;

double GetCurrentPrice() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

double GetDistancePips(double price1, double price2) {
   return (price1 - price2) / _Point / 10;
}

void ManageCloseOrder() {
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

double GetCandleLow(int shift) {
   return iLow(Symbol(), PERIOD_H1, shift);
}

double PreviousLowH1() {
   double lowestLow = GetCandleLow(1);
   
   for(int i=2; i<=10; i++) {
      double candleLow = GetCandleLow(i);
      
      if(candleLow < lowestLow) {
         lowestLow = candleLow;
      }
   }
   return lowestLow;
}

void SetStopLossAll() {
   double sl = PreviousLowH1();
   
   for(int i = PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket)) {
         double currentSL = PositionGetDouble(POSITION_SL);
         
         if(currentSL == 0) {
            if(trade.PositionModify(ticket, sl, 0)) {
               Print("SL set for ticket: ", ticket);
            }
         }
      }
   }
}

void OnTick() {

   ManageCloseOrder();
   
   SetStopLossAll();

   double currentPrice = GetCurrentPrice();
   
   if(PositionsTotal() == 0) {
      if(trade.Buy(LotSize)) {
         lastOpenPrice = currentPrice;
         Print("Buy Opened");
      }
      return;
   }

   double distance = GetDistancePips(currentPrice, lastOpenPrice);

   if(distance >= 60) {
      if(trade.Buy(LotSize)) {
         lastOpenPrice = currentPrice;
         Print("New Buy Opened at 60 pips");
      }
   }
}