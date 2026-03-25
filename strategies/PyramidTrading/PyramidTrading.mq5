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
input double DailyDDLimitPct = 2.0;  // หยุดเทรดถ้า equity ลดเกินกี่ % ต่อวัน
input double MaxDDLimitPct   = 10.0; // หยุดถาวรถ้า equity ลดเกินกี่ % จาก starting balance
input double EMAGapPips      = 5.0; // close ต้องห่าง EMA อย่างน้อย (pips)
input double EMASlopeMin     = 2.0;  // EMA slope ขั้นต่ำ (pips) — ถ้าน้อยกว่านี้ถือว่าแบน
input double BodyRatioMin    = 50.0; // body ต้องเกินกี่ % ของ range

double   dailyStartEquity = 0;
bool     maxDDBreached    = false;
double   lastOpenPrice    = 0;
double   startingBalance  = 0;
int      emaHandle        = INVALID_HANDLE;
int      atrHandle        = INVALID_HANDLE;
datetime lastH4Time       = 0;

// ==========================================

int OnInit() {
   startingBalance  = (InitialBalance > 0) ? InitialBalance
                                           : AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("Starting balance: $", DoubleToString(startingBalance, 2));

   emaHandle = iMA(Symbol(), PERIOD_H4, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Failed to create EMA handle");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
}

double GetCurrentPrice() {
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

double GetDistancePips(double price1, double price2) {
   return (price1 - price2) / _Point / 10;
}

// ==========================================
// H4 FILTER
// ==========================================

bool IsH4Uptrend() {
   // ดึง EMA 6 ค่า shift 1-6
   double emaVal[6];
   if(CopyBuffer(emaHandle, 0, 1, 6, emaVal) <= 0) {
      Print("EMA copy failed: ", GetLastError());
      return false;
   }
   // emaVal[0]=shift1, emaVal[1]=shift2, ..., emaVal[4]=shift5

   double ema1 = emaVal[0];
   double ema5 = emaVal[4];

   // ดึง ATR
   double atrVal[1];
   if(CopyBuffer(atrHandle, 0, 1, 1, atrVal) <= 0) {
      Print("ATR copy failed: ", GetLastError());
      return false;
   }
   double atr = atrVal[0];

   double h4Close1 = iClose(Symbol(), PERIOD_H4, 1);
   double h4Close2 = iClose(Symbol(), PERIOD_H4, 2);
   double h4Open1  = iOpen (Symbol(), PERIOD_H4, 1);
   double h4High1  = iHigh (Symbol(), PERIOD_H4, 1);
   double h4Low1   = iLow  (Symbol(), PERIOD_H4, 1);
   double h4High2  = iHigh (Symbol(), PERIOD_H4, 2);
   double h4High0  = iHigh (Symbol(), PERIOD_H4, 0);

   // เงื่อนไข 1: ยืนเหนือ EMA 2 แท่งติดกัน
   if(h4Close1 <= ema1) {
      Print("H4 filter: close[1] below EMA"); return false;
   }
   if(h4Close2 <= emaVal[1]) {
      Print("H4 filter: close[2] below EMA"); return false;
   }

   // เงื่อนไข 2: ห่าง EMA อย่างน้อย EMAGapPips
   double gapPips = (h4Close1 - ema1) / _Point / 10;
   if(gapPips < EMAGapPips) {
      Print("H4 filter: too close to EMA — ", DoubleToString(gapPips, 1),
            " pips (min ", EMAGapPips, ")");
      return false;
   }

   // เงื่อนไข 3: EMA slope ต้องชี้ขึ้น
   double slopePips = (ema1 - ema5) / _Point / 10;
   if(slopePips < EMASlopeMin) {
      Print("H4 filter: EMA slope too flat — ", DoubleToString(slopePips, 1),
            " pips (min ", EMASlopeMin, ")");
      return false;
   }

   // เงื่อนไข 5: body > BodyRatioMin % ของ range
   double body  = h4Close1 - h4Open1;
   double range = h4High1  - h4Low1;
   if(body <= 0 || range <= 0) {
      Print("H4 filter: invalid candle"); return false;
   }
   double bodyRatio = (body / range) * 100.0;
   if(bodyRatio < BodyRatioMin) {
      Print("H4 filter: body too small — ", DoubleToString(bodyRatio, 1),
            "% (min ", BodyRatioMin, "%)");
      return false;
   }

   Print("H4 filter: passed ✓",
         " | gap=",   DoubleToString(gapPips, 1),   " pips",
         " | slope=", DoubleToString(slopePips, 1), " pips",
         " | body=",  DoubleToString(bodyRatio, 1), "%");
   return true;
}

// ==========================================
// DRAWDOWN PROTECTION
// ==========================================

bool IsDailyDDBreached() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = (dailyStartEquity - equity) / dailyStartEquity * 100.0;
   if(ddPct >= DailyDDLimitPct) {
      Print("⛔ Daily DD limit reached: ", DoubleToString(ddPct, 2),
            "% (max ", DailyDDLimitPct, "%) — stop trading today");
      return true;
   }
   return false;
}

bool IsMaxDDBreached() {
   if(maxDDBreached) {
      Print("⛔ Max DD already breached — manual reset required");
      return true;
   }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = (startingBalance - equity) / startingBalance * 100.0;
   if(ddPct >= MaxDDLimitPct) {
      maxDDBreached = true;
      Print("🚨 Max DD breached: ", DoubleToString(ddPct, 2),
            "% (max ", MaxDDLimitPct, "%) — EA stopped, reset InitialBalance to resume");
      return true;
   }
   return false;
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
   static datetime lastDay = 0;
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != lastDay) {
      lastDay          = today;
      dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("📅 New day — daily equity reset: $", DoubleToString(dailyStartEquity, 2));
   }

   ManageCloseOrder();
   SetStopLossAll();
   TrailingSL();

   if(IsMaxDDBreached())   return;
   if(IsDailyDDBreached()) return;

   static bool h4Signal = false;
   datetime currentH4Time = iTime(Symbol(), PERIOD_H4, 0);
   if(currentH4Time != lastH4Time) {
      lastH4Time = currentH4Time;
      h4Signal   = IsH4Uptrend();
   }
   //if(!h4Signal) return;

   double currentPrice = GetCurrentPrice();
   double sl           = PreviousLowH1();
   if(sl >= currentPrice) return;
   
   // ===== EMA FILTER =====
   double emaNow[];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaNow) <= 0) return;

   double ema = emaNow[0];

   // ❌ ถ้าอยู่ใต้ EMA → ไม่เทรดเลย
   if(currentPrice <= ema) return;
   
   double close1 = iClose(Symbol(), PERIOD_H4, 1);
   if(close1 <= ema) return;

   double lot     = GetCurrentLot();
   double newRisk = GetOrderRisk(currentPrice, sl, lot);

   if(PositionsTotal() == 0) {
      if(CheckTotalRisk(newRisk)) {
         ShowRiskInfo(lot, newRisk);
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
      if(CheckTotalRisk(newRisk)) {
         ShowRiskInfo(lot, newRisk);
         if(trade.Buy(lot)) {
            lastOpenPrice = currentPrice;
            Print("New Buy | Lot: ", DoubleToString(lot, 2), " | Risk Ok");
         }
      }
      else Print("Risk cap reached — skip order");
   }
}