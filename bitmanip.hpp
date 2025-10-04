#pragma once

#include <iostream>
#include <type_traits>
#include <iomanip>

/**
 * @brief Helper functions for common bit manipulation tasks.
 *
 * All functions use C++ templates (typename T) to work with any integer type
 * (int, unsigned int, long long, etc.). Positions start from 0 (LSB).
 */

// --- Utility Functions ---

/**
 * @brief Prints the value and its binary representation.
 * @tparam T The integer type.
 * @param name The name of the value.
 * @param value The value to print.
 */
template <typename T>
void print_binary(const char* name, T value) {
    // Determine the number of bits based on the type T
    constexpr size_t BITS = sizeof(T) * 8;
    std::cout << std::setw(15) << std::left << name << ": ";

    // Iterate from MSB to LSB
    for (size_t i = 0; i < BITS; ++i) {
        // Use an unsigned type for shifting to prevent undefined behavior
        // if T is signed and negative, though typically used on positive values.
        using UT = typename std::make_unsigned<T>::type;
        UT u_value = static_cast<UT>(value);
        
        // Check if the i-th bit from the left (BITS - 1 - i) is set
        if ((u_value >> (BITS - 1 - i)) & 1) {
            std::cout << "1";
        } else {
            std::cout << "0";
        }

        // Add a space every 8 bits for readability
        if ((i + 1) % 8 == 0 && (i + 1) != BITS) {
            std::cout << " ";
        }
    }
    std::cout << " (Dec: " << std::dec << value << ")" << std::endl;
}

// --- Single Bit Operations ---

/**
 * @brief Checks if a specific bit at 'pos' is set (1).
 * @tparam T The integer type.
 * @param value The integer value.
 * @param pos The bit position (0-indexed, LSB).
 * @return true if the bit is set, false otherwise.
 */
template <typename T>
bool is_bit_set(T value, unsigned int pos) {
    return (value & (static_cast<T>(1) << pos)) != 0;
}

/**
 * @brief Sets a specific bit at 'pos' to 1.
 * @tparam T The integer type.
 * @param value The integer value to modify.
 * @param pos The bit position (0-indexed, LSB).
 * @return The modified value with the bit set.
 */
template <typename T>
T set_bit(T value, unsigned int pos) {
    return value | (static_cast<T>(1) << pos);
}

/**
 * @brief Clears a specific bit at 'pos' to 0.
 * @tparam T The integer type.
 * @param value The integer value to modify.
 * @param pos The bit position (0-indexed, LSB).
 * @return The modified value with the bit cleared.
 */
template <typename T>
T clear_bit(T value, unsigned int pos) {
    return value & ~(static_cast<T>(1) << pos);
}

/**
 * @brief Toggles a specific bit at 'pos'.
 * @tparam T The integer type.
 * @param value The integer value to modify.
 * @param pos The bit position (0-indexed, LSB).
 * @return The modified value with the bit toggled.
 */
template <typename T>
T toggle_bit(T value, unsigned int pos) {
    return value ^ (static_cast<T>(1) << pos);
}

// --- Multi-Bit Field Operations ---

/**
 * @brief Extracts a field of 'num_bits' starting at 'start_pos'.
 * @tparam T The integer type.
 * @param value The integer value to extract from.
 * @param start_pos The starting bit position (0-indexed, LSB).
 * @param num_bits The number of bits in the field to extract.
 * @return The extracted field, right-justified (LSB).
 */
template <typename T>
T extract_bits(T value, unsigned int start_pos, unsigned int num_bits) {
    if (num_bits == 0) return 0;

    // Create a mask of 'num_bits' ones. Use the unsigned version of T for safety.
    using UT = typename std::make_unsigned<T>::type;
    // Handle potential UB if num_bits is the size of T (e.g. 32 for a 32-bit int),
    // where (1 << 32) is UB. If num_bits equals the size of T, the mask is all ones.
    UT mask;
    if (num_bits >= sizeof(T) * 8) {
        mask = static_cast<UT>(-1); // All bits set
    } else {
        mask = (static_cast<UT>(1) << num_bits) - 1;
    }


    // Shift the value right to align the field to the LSB, then apply the mask.
    T extracted = (value >> start_pos) & static_cast<T>(mask);
    return extracted;
}

/**
 * @brief Inserts a 'source' value field into the 'target' value.
 * @tparam T The integer type.
 * @param target The original value where bits will be inserted.
 * @param source The value containing the bits to insert (assumed to be right-justified).
 * @param start_pos The starting bit position (0-indexed, LSB) in the target.
 * @param num_bits The number of bits to insert.
 * @return The modified target value with the source inserted.
 */
template <typename T>
T insert_bits(T target, T source, unsigned int start_pos, unsigned int num_bits) {
    if (num_bits == 0) return target;

    // Use the unsigned version of T for safe mask creation.
    using UT = typename std::make_unsigned<T>::type;

    // 1. Create a mask for the target field: 'num_bits' ones shifted to 'start_pos'.
    UT field_mask;
    if (num_bits >= sizeof(T) * 8) {
        field_mask = static_cast<UT>(-1);
    } else {
        field_mask = ((static_cast<UT>(1) << num_bits) - 1) << start_pos;
    }

    // 2. Clear the target field
    target &= ~field_mask;

    // 3. Prepare the source: mask it (to ensure only relevant bits are used) and shift it to position.
    UT source_mask;
    if (num_bits >= sizeof(T) * 8) {
        source_mask = static_cast<UT>(-1);
    } else {
        source_mask = (static_cast<UT>(1) << num_bits) - 1;
    }
    
    // Mask the source and then shift it
    T shifted_source = (source & static_cast<T>(source_mask)) << start_pos;

    // 4. Combine the cleared target and the shifted source.
    return target | shifted_source;
}
