// Test Map and Set implementations

console.log("=== Map Tests ===");

// Create a new Map
const map = new Map();
console.log("Created new Map");
console.log("Size:", map.size); // Should be 0

// Test set and get
map.set("key1", "value1");
map.set("key2", "value2");
console.log("After adding 2 entries, size:", map.size); // Should be 2
console.log("Get key1:", map.get("key1")); // Should be "value1"
console.log("Get key2:", map.get("key2")); // Should be "value2"
console.log("Get nonexistent:", map.get("key3")); // Should be undefined

// Test has
console.log("Has key1:", map.has("key1")); // Should be true
console.log("Has key3:", map.has("key3")); // Should be false

// Test delete
console.log("Delete key1:", map.delete("key1")); // Should be true
console.log("After delete, size:", map.size); // Should be 1
console.log("Has key1 after delete:", map.has("key1")); // Should be false
console.log("Delete nonexistent:", map.delete("key3")); // Should be false

// Test clear
map.set("a", 1);
map.set("b", 2);
console.log("Before clear, size:", map.size);
map.clear();
console.log("After clear, size:", map.size); // Should be 0

// Test with different key types
map.set(1, "number key");
map.set(true, "boolean key");
map.set(null, "null key");
console.log("Get number key:", map.get(1));
console.log("Get boolean key:", map.get(true));
console.log("Get null key:", map.get(null));

// Test NaN equality (SameValueZero)
map.set(NaN, "NaN value");
console.log("Get NaN:", map.get(NaN)); // Should work because NaN === NaN in SameValueZero

console.log("\n=== Set Tests ===");

// Create a new Set
const set = new Set();
console.log("Created new Set");
console.log("Size:", set.size); // Should be 0

// Test add
set.add("value1");
set.add("value2");
console.log("After adding 2 values, size:", set.size); // Should be 2

// Test add duplicate
set.add("value1");
console.log("After adding duplicate, size:", set.size); // Should still be 2

// Test has
console.log("Has value1:", set.has("value1")); // Should be true
console.log("Has value3:", set.has("value3")); // Should be false

// Test delete
console.log("Delete value1:", set.delete("value1")); // Should be true
console.log("After delete, size:", set.size); // Should be 1
console.log("Has value1 after delete:", set.has("value1")); // Should be false
console.log("Delete nonexistent:", set.delete("value3")); // Should be false

// Test clear
set.add("a");
set.add("b");
console.log("Before clear, size:", set.size);
set.clear();
console.log("After clear, size:", set.size); // Should be 0

// Test with different value types
set.add(1);
set.add(true);
set.add(null);
console.log("Has number 1:", set.has(1));
console.log("Has boolean true:", set.has(true));
console.log("Has null:", set.has(null));

// Test NaN equality (SameValueZero)
set.add(NaN);
set.add(NaN); // Should not add duplicate
console.log("After adding NaN twice, has NaN:", set.has(NaN)); // Should be true
console.log("Size after adding NaN twice:", set.size); // Should not have duplicates

console.log("\n=== Map from iterable ===");
const map2 = new Map([["a", 1], ["b", 2], ["c", 3]]);
console.log("Map from array, size:", map2.size); // Should be 3
console.log("Get 'a':", map2.get("a")); // Should be 1

console.log("\n=== Set from iterable ===");
const set2 = new Set([1, 2, 3, 2, 1]);
console.log("Set from array, size:", set2.size); // Should be 3 (no duplicates)
console.log("Has 1:", set2.has(1)); // Should be true
console.log("Has 4:", set2.has(4)); // Should be false

console.log("\n=== All tests completed ===");
