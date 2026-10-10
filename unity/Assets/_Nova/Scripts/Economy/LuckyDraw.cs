using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Economy
{
    /// <summary>
    /// Lucky Draw engine — CODM's draw rules, ported from Godot lucky_draw.gd:
    ///  - 10 slots, each spin costs an escalating NP amount
    ///    (30, 60, 110, 180, 270, 380, 510, 660, 830, 1020)
    ///  - Owned items are REMOVED from the pool (never win duplicates)
    ///  - The 10th (final) spin GUARANTEES the top (mythic) prize
    ///  - Otherwise each spin draws from the remaining pool weighted by odds
    ///    (mythic 3% / epic 12% / rare 30% / common 55%), re-weighted over
    ///    whatever is left
    ///  - Draw state (spins used, won items) persists in the wallet.
    ///
    /// All draws are pure logic + wallet calls; UI lives in StoreUI.
    /// </summary>
    public static class LuckyDraw
    {
        public struct SpinResult
        {
            public bool Ok;
            public string Reason;     // failure reason when !Ok
            public int WonIdx;        // item index in DrawDef.Items
            public DrawItemKind Kind;
            public string Label;      // display label of the won item
            public string SkinId;     // mythic wins only: unlocked skin id
            public bool Guaranteed;   // true when this was the final mythic guarantee
            public int SpinsUsed;     // spins used after this spin
        }

        /// <summary>Cost of the next spin given how many spins are already used.
        /// Returns -1 when the draw is complete/invalid.</summary>
        public static int SpinCost(int spinsUsed)
        {
            if (spinsUsed < 0 || spinsUsed >= StoreData.DrawSpinCosts.Length) return -1;
            return StoreData.DrawSpinCosts[spinsUsed];
        }

        /// <summary>Remaining item indices in the pool after removing won ones.</summary>
        public static List<int> RemainingPool(string drawId)
        {
            DrawDef draw = StoreData.DrawById(drawId);
            var outp = new List<int>();
            if (draw.Items == null) return outp;
            NpWallet.DrawState st = NpWallet.GetDrawState(drawId);
            for (int i = 0; i < draw.Items.Length; i++)
                if (!st.Won.Contains(i)) outp.Add(i);
            return outp;
        }

        /// <summary>
        /// Perform one spin. Reads pool + wallet state, debits NP, grants the
        /// item, records the win. All-or-nothing: if NP is insufficient nothing
        /// is spent and no item is granted.
        /// </summary>
        public static SpinResult Spin(string drawId, System.Random rng)
        {
            DrawDef draw = StoreData.DrawById(drawId);
            if (draw.Id == null)
                return new SpinResult { Ok = false, Reason = "unknown draw" };

            NpWallet.DrawState st = NpWallet.GetDrawState(drawId);
            int spinsUsed = st.Won.Count;
            int cost = SpinCost(spinsUsed);
            if (cost < 0)
                return new SpinResult { Ok = false, Reason = "draw complete" };

            List<int> pool = RemainingPool(drawId);
            if (pool.Count == 0)
                return new SpinResult { Ok = false, Reason = "pool empty" };

            if (!NpWallet.Spend(cost, "draw:" + drawId + " spin " + (spinsUsed + 1)))
                return new SpinResult { Ok = false, Reason = "insufficient NP" };

            // Final spin: guarantee the mythic (it is the only item left).
            bool guaranteed = false;
            int pickIdx;
            if (pool.Count == 1)
            {
                pickIdx = pool[0];
                guaranteed = draw.Items[pickIdx].Kind == DrawItemKind.Mythic;
            }
            else
            {
                // Weighted draw over the remaining pool.
                float total = 0f;
                float[] weights = new float[pool.Count];
                for (int i = 0; i < pool.Count; i++)
                {
                    weights[i] = StoreData.DrawOdds(draw.Items[pool[i]].Kind);
                    total += weights[i];
                }
                int pi;
                if (total <= 0f)
                {
                    pi = rng.Next(0, pool.Count);
                }
                else
                {
                    float roll = (float)rng.NextDouble() * total;
                    float acc = 0f;
                    pi = pool.Count - 1;
                    for (int i = 0; i < pool.Count; i++)
                    {
                        acc += weights[i];
                        if (roll <= acc) { pi = i; break; }
                    }
                }
                pickIdx = pool[pi];
            }

            DrawItem item = draw.Items[pickIdx];
            string skinId = "";
            if (item.Kind == DrawItemKind.Mythic)
            {
                skinId = NpWallet.SkinId(item.Gun, item.SkinIdx);
                NpWallet.UnlockSkin(skinId);
            }
            else
            {
                NpWallet.GrantFlair(StoreData.ItemLabel(item));
            }
            NpWallet.RecordDrawWin(drawId, pickIdx);

            return new SpinResult
            {
                Ok = true,
                WonIdx = pickIdx,
                Kind = item.Kind,
                Label = StoreData.ItemLabel(item),
                SkinId = skinId,
                Guaranteed = guaranteed,
                SpinsUsed = spinsUsed + 1,
            };
        }

        /// <summary>Remaining NP to finish the draw from the current state.</summary>
        public static int RemainingCost(string drawId)
        {
            NpWallet.DrawState st = NpWallet.GetDrawState(drawId);
            int t = 0;
            for (int i = st.Won.Count; i < StoreData.DrawSpinCosts.Length; i++)
                t += StoreData.DrawSpinCosts[i];
            return t;
        }
    }
}
