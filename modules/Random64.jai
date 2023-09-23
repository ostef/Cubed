// This module was copied from the Random module shipped with the Jai compiler
// It includes changes in names and API, every function now takes a *RNG as
// parameter. RandomGetU64 also returns the rng after modifying it, and not before
// which means you can do seed = RandomGetU64 (rng); RandomSeed (rng);

/*

This is a very simple random number generator of the MCG type.

It is from the "Today's 64-bit Minimal Standard" section of https://www.pcg-random.org/posts/does-it-beat-the-minimal-standard.html.

*/

RandomGetU64 :: inline (rng : *RNG) -> u64 {
    FACTOR_HIGH : u64 : 0x0fc9_4e3b_f4e9_ab32;
    FACTOR_LOW  : u64 : 0x8664_58cd_56f5_e605;

    // A 128-bit multiply.
    // @Copypasta from modules/Basic/Apollo_Time.jai, but probably worth having
    // separately here so as not to create a dependency.
    // We can re-evaluate this as code gets big.
    //
    // All we are doing here is:
    //
    //     state = state * FACTOR;
    //
    // where 'state' and 'FACTOR' are 128-bit unsigned integers.
    //

    #if CPU == .X64 {
        #asm {
            result_high: gpr === d;
            result_low:  gpr === a;

            factor:   gpr;
            high_sum: gpr;
            low_storage: gpr;  // Hold this until we are ready to write it out.

            // Low times low:
            mov result_low, [rng + 0];  // This is input as well as result.
            mov factor,     FACTOR_LOW;

            mul result_high, result_low, factor;

            mov low_storage, result_low;  // Hold onto this for a while, please.
            mov high_sum, result_high;    // Store the high part.

            // High a times low b. 'factor' still holds low b.
            mov result_low, [rng + 8];
            mul result_high, result_low, factor;
            add high_sum, result_low;

            // Low a times high b.
            mov result_low, [rng + 0];
            mov factor,     FACTOR_HIGH;
            mul result_high, result_low, factor;
            add high_sum, result_low;

            // High a times high b is discarded.

            mov [rng + 8], high_sum;
            mov [rng + 0], low_storage;
        }
    } else {
        mul64_high, mul64_low := Basic.multiply_64bits_with_overflow(rng.low, FACTOR_LOW);

        rng.high = mul64_high + (rng.high * FACTOR_LOW) + (rng.low * FACTOR_HIGH);
        rng.low  = mul64_low; // Don't put this before p.high, as p.high uses the old value of p.low.
    }

    return rng.high;
}

RandomSeed :: inline (rng : *RNG, new_seed : u64) {
    // The only requirement is that the seed be odd.
    // If you only give us 1 u64 (which we support for ease-of-use reasons)
    // we will just put a 1 in the bottom slot, so it's odd.

    rng.low  = 1;
    rng.high = new_seed;
}

RandomSeed :: inline (rng : *RNG, new_seed: RNG) {
    // If you want to do the big seed.

    rng.* = new_seed;
    rng.low |= 1;   // Low must be an odd number.
}

// It's often useful to get a floating-point number in the range [0, 1].
RandomGetZeroToOne :: (rng : *RNG) -> float {
    randint := RandomGetU64(rng) & MASK;
    return randint / cast(float) MASK;
}

// This one gives a floating-point number in the range [0, 1).
RandomGetZeroToOneOpen :: (rng : *RNG) -> float {
    randint := RandomGetU64(rng) & MASK;
    return randint / cast(float) RANDRANGE;
}

// It's often useful to get a floating-point number in some floating-point range [min, max].
RandomRangeFloat :: (rng : *RNG, min: float, max: float) -> float {
    // We allow min and max to be flipped, no big whoop.

    randint := RandomGetU64 (rng) & MASK;
    addition := (randint / cast(float) MASK) * (max - min);

    result := min + addition;

    // Deal with floating-point inaccuracy (@Speed: Can this actually happen?)
    if result > max  result = max;
    if result < min  result = min;

    return result;
}

RandomChance :: (rng : *RNG, chance : float) -> bool
{
    return RandomGetZeroToOneOpen (rng) < chance;
}

RNG :: struct {
    low :  u64;
    high : u64;
}

#scope_file

Basic :: #import "Basic";

RANDRANGE : u32 : 1 << 24;  // Not using all the bits for stuff like float divides, because we start losing accuracy due to the max representable integer. Maybe could be smarter than this. Must be a power of two for MASK to work. The highest exactly-representable integer in float32 is 2**24.
MASK :: RANDRANGE - 1;
#assert (RANDRANGE & MASK) == 0;

// Obviously, we picked an arbitrary number for state.
// State must be relatively prime with the modulus, which is 0x7fff_ffff.
#add_context random_number_generator := RNG.{1, 0};
