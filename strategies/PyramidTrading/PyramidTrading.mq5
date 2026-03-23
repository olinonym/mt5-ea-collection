//+------------------------------------------------------------------+
//|                                               PyramidTrading.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Trade/Trade.mqh>
CTrade trade;

input double BaseLot         = 0.02;  // Lot เริ่มต้น
input double LotStep         = 0.01;  // ขยับ lot ทีละเท่าไหร่
input double BalanceStep     = 500.0; // ขยับ lot ทุกๆ balance เพิ่มขึ้น $X
input double InitialBalance  = 0.0;   // Balance ตอนเริ่มต้น (0 = ดึงอัตโนมัติ)
input double TotalRiskCapPct = 3.0;   // Total risk สูงสุด (% ของ Equity)
input int    EMA_Period      = 50;    // Period ของ EMA H4

double lastOpenPrice   = 0;
double startingBalance = 0;
int    emaHandle       = INVALID_HANDLE;

// ==========================================

int OnInit() {
   startingBalance = (InitialBalance > 0) ? InitialBalance
                                          : AccountInfoDouble(ACCOUNT_BALANCE);
   Print("Starting balance: $", DoubleToString(startingBalance, 2));

   emaHandle = iMA(Symbol(), PERIOD_H4, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Failed to create EMA handle");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

double GetCurrentPrice() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

double GetDistancePips(double price1, double price2) {
   return (price1 - price2) / _Point / 10;
}

// ==========================================
// EMA FILTER
// ==========================================

bool IsH4Uptrend() {
   double emaVal[1];
   if(CopyBuffer(emaHandle, 0, 1, 1, emaVal) <= 0) {
      Print("EMA copy failed: ", GetLastError());
      return false;
   }

   double h4Close = iClose(Symbol(), PERIOD_H4, 1);
   double h4Open  = iOpen (Symbol(), PERIOD_H4, 1);

   // เงื่อนไข 1: candle H4 shift 1 ต้องเป็น bullish
   if(h4Close <= h4Open) {
      Print("EMA filter: H4 candle not bullish");
      return false;
   }

   // เงื่อนไข 2: close ต้องอยู่เหนือ EMA50
   if(h4Close <= emaVal[0]) {
      Print("EMA filter: H4 close below EMA50");
      return false;
   }

   Print("EMA filter: passed ✓ | H4 close=", DoubleToString(h4Close, _Digits),
         " EMA=", DoubleToString(emaVal[0], _Digits));
   return true;
}

// ==========================================
// LOT STEPPING
// ==========================================

double GetCurrentLot() {
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double growth     = balance - startingBalance;
   int    steps      = (int)MathFloor(MathMax(growth, 0) / BalanceStep);
   double lot        = BaseLot + steps * LotStep;

   double brokerStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / brokerStep) * brokerStep;

   double lotMin = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   return MathMax(lotMin, MathMin(lotMax, lot));
}

// ==========================================
// RISK MANAGEMENT
// ==========================================

double GetOrderRisk(double entry, double sl, double lot) {
   double slPips = MathAbs(entry - sl) / _Point / 10;
   return slPips * lot * 10;
}

double GetTotalRisk() {
   double totalRisk = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl        = PositionGetDouble(POSITION_SL);
         double lot       = PositionGetDouble(POSITION_VOLUME);
         if(sl > 0)
            totalRisk += GetOrderRisk(openPrice, sl, lot);
      }
   }
   return totalRisk;
}

bool CheckTotalRisk(double newRisk) {
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalCapAmt = equity * TotalRiskCapPct / 100.0;
   return (GetTotalRisk() + newRisk <= totalCapAmt);
}

void ShowRiskInfo(double lot, double newRisk) {
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double totalCapAmt = equity * TotalRiskCapPct / 100.0;
   double currentRisk = GetTotalRisk();

   Print("=== Risk Info ===");
   Print("Balance: $",            DoubleToString(balance, 2),
         " | Growth: $",          DoubleToString(balance - startingBalance, 2));
   Print("Lot: ",                 DoubleToString(lot, 2));
   Print("Equity: $",             DoubleToString(equity, 2));
   Print("Risk cap (",            TotalRiskCapPct, "%): $", DoubleToString(totalCapAmt, 2));
   Print("Current total risk: $", DoubleToString(currentRisk, 2));
   Print("New order risk: $",     DoubleToString(newRisk, 2));
   Print("After open: $",         DoubleToString(currentRisk + newRisk, 2));
}

// ==========================================
// POSITION MANAGEMENT
// ==========================================

void ManageCloseOrder() {
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume       = PositionGetDouble(POSITION_VOLUME);
         double currentPrice = GetCurrentPrice();
         double profitPips   = (currentPrice - openPrice) / _Point / 10;

         if(profitPips >= 180) {
            if(trade.PositionClose(ticket))
               Print("Closed 100% | Ticket: ", ticket);
         }
         else if(profitPips >= 120) {
            double closeLot = volume / 2;
            if(closeLot >= 0.01)
               if(trade.PositionClosePartial(ticket, closeLot))
                  Print("Close 50% | Ticket: ", ticket);
         }
      }
   }
}

double GetCandleLow(int shift) {
   return iLow(Symbol(), PERIOD_H1, shift);
}

double PreviousLowH1() {
   double lowestLow = GetCandleLow(1);
   for(int i = 2; i <= 10; i++) {
      double candleLow = GetCandleLow(i);
      if(candleLow < lowestLow) lowestLow = candleLow;
   }
   return lowestLow;
}

void SetStopLossAll() {
   double sl = PreviousLowH1();
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(currentSL == 0) {
            if(trade.PositionModify(ticket, sl, 0))
               Print("SL set for ticket: ", ticket);
         }
      }
   }
}

void TrailingSL() {
   double triggerPips = 60;
   double lockPips    = 10;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
         double current    = GetCurrentPrice();
         double slCurrent  = PositionGetDouble(POSITION_SL);
         double profitPips = (current - openPrice) / _Point / 10;

         if(profitPips >= triggerPips) {
            double newSL = openPrice + (lockPips * 10 * _Point);
            if(slCurrent < newSL) {
               if(trade.PositionModify(ticket, newSL, 0))
                  Print("Trailing SL updated to: ", newSL);
               else
                  Print("Modify failed: ", GetLastError());
            }
         }
      }
   }
}

// ==========================================
// OnTick
// ==========================================

void OnTick() {
   ManageCloseOrder();
   SetStopLossAll();
   TrailingSL();

   // กรอง EMA ก่อนทุกอย่าง
   if(!IsH4Uptrend()) return;

   double currentPrice = GetCurrentPrice();
   double sl           = PreviousLowH1();

   if(sl >= currentPrice) return;

   double lot     = GetCurrentLot();
   double newRisk = GetOrderRisk(currentPrice, sl, lot);

   if(PositionsTotal() == 0) {
      ShowRiskInfo(lot, newRisk);
      if(CheckTotalRisk(newRisk)) {
         if(trade.Buy(lot)) {
            lastOpenPrice = currentPrice;
            Print("First Buy | Lot: ", DoubleToString(lot, 2));
         }
      }
      else Print("Risk cap reached — skip order");
      return;
   }

   double distance = GetDistancePips(currentPrice, lastOpenPrice);
   if(distance >= 60) {
      ShowRiskInfo(lot, newRisk);
      if(CheckTotalRisk(newRisk)) {
         if(trade.Buy(lot)) {
            lastOpenPrice = currentPrice;
            Print("New Buy | Lot: ", DoubleToString(lot, 2), " | Risk Ok");
         }
      }
      else Print("Risk cap reached — skip order");
   }
}