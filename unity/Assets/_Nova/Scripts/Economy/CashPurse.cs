using System;
using UnityEngine;

namespace NovaMobile.Economy
{
    /// <summary>
    /// Match-scoped BR cash economy. Cash is earned from kills, loot pickups
    /// and safes, and spent at buy stations. Match-scoped: Reset() at match
    /// start. Not persisted (unlike NP, which is the account wallet).
    /// Ported from the cash side of Godot buy_station.gd / main.gd.
    /// </summary>
    public static class CashPurse
    {
        private static int _cash;
        private static int _earnedThisMatch;

        public static event Action<int> Changed;   // new balance

        public static int Balance
        {
            get { return _cash; }
        }

        public static int EarnedThisMatch
        {
            get { return _earnedThisMatch; }
        }

        public static void Reset()
        {
            _cash = 0;
            _earnedThisMatch = 0;
            if (Changed != null) Changed(_cash);
        }

        /// <summary>Earn cash (kill reward, loot cash, safe). Ignores non-positive.</summary>
        public static void Earn(int amount, string reason)
        {
            if (amount <= 0) return;
            _cash += amount;
            _earnedThisMatch += amount;
            if (Changed != null) Changed(_cash);
        }

        /// <summary>
        /// Spend cash atomically. False = insufficient (no debit).
        /// </summary>
        public static bool Spend(int amount, string reason)
        {
            if (amount <= 0) return true;
            if (_cash < amount) return false;
            _cash -= amount;
            if (Changed != null) Changed(_cash);
            return true;
        }
    }
}
