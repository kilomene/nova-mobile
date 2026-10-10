using System;
using System.Collections.Generic;
using UnityEngine;

namespace NovaMobile.Core
{
    /// <summary>Generic object pool. Preallocate, then Rent/Return with zero GC in hot paths.</summary>
    public sealed class ObjectPool<T> where T : Component
    {
        private readonly Stack<T> _free = new Stack<T>();
        private readonly T _prefab;
        private readonly Transform _parent;

        public ObjectPool(T prefab, int preallocate, Transform parent = null)
        {
            _prefab = prefab;
            _parent = parent;
            for (int i = 0; i < preallocate; i++)
            {
                T inst = UnityEngine.Object.Instantiate(_prefab, _parent);
                inst.gameObject.SetActive(false);
                _free.Push(inst);
            }
        }

        public T Rent()
        {
            T inst = _free.Count > 0 ? _free.Pop() : UnityEngine.Object.Instantiate(_prefab, _parent);
            inst.gameObject.SetActive(true);
            return inst;
        }

        public void Return(T inst)
        {
            inst.gameObject.SetActive(false);
            _free.Push(inst);
        }

        public int FreeCount => _free.Count;
    }

    /// <summary>Shared math / misc helpers. No allocations.</summary>
    public static class NovaUtils
    {
        private static System.Random _rng = new System.Random();

        public static void Reseed(int seed) { _rng = new System.Random(seed); }

        public static float Range(float min, float max)
        {
            return min + (float)_rng.NextDouble() * (max - min);
        }

        public static int RangeInt(int minInclusive, int maxExclusive)
        {
            return _rng.Next(minInclusive, maxExclusive);
        }

        /// <summary>Weighted pick over parallel arrays. Returns index.</summary>
        public static int WeightedPick(float[] weights)
        {
            float total = 0f;
            for (int i = 0; i < weights.Length; i++) total += weights[i];
            float r = (float)_rng.NextDouble() * total;
            for (int i = 0; i < weights.Length; i++)
            {
                r -= weights[i];
                if (r <= 0f) return i;
            }
            return weights.Length - 1;
        }

        /// <summary>Position a RectTransform by screen fractions (0..1), CODM-style HUD layout.</summary>
        public static void PlaceByFraction(RectTransform rt, float xMin, float yMin, float xMax, float yMax)
        {
            rt.anchorMin = new Vector2(xMin, yMin);
            rt.anchorMax = new Vector2(xMax, yMax);
            rt.offsetMin = Vector2.zero;
            rt.offsetMax = Vector2.zero;
        }

        public static float Clamp01(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }

        public static float DampAngle(float current, float target, float lambda, float dt)
        {
            return Mathf.LerpAngle(current, target, 1f - Mathf.Exp(-lambda * dt));
        }
    }
}
