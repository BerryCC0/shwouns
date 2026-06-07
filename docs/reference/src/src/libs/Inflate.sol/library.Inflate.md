# Inflate
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/libs/Inflate.sol)

Based on https://github.com/madler/zlib/blob/master/contrib/puff

Modified the original code for gas optimizations
1. Disable overflow/underflow checks
2. Chunk some loop iterations


## Constants
### MAXBITS

```solidity
uint256 constant MAXBITS = 15
```


### MAXLCODES

```solidity
uint256 constant MAXLCODES = 286
```


### MAXDCODES

```solidity
uint256 constant MAXDCODES = 30
```


### MAXCODES

```solidity
uint256 constant MAXCODES = (MAXLCODES + MAXDCODES)
```


### FIXLCODES

```solidity
uint256 constant FIXLCODES = 288
```


## Functions
### bits


```solidity
function bits(State memory s, uint256 need) private pure returns (ErrorCode, uint256);
```

### _stored


```solidity
function _stored(State memory s) private pure returns (ErrorCode);
```

### _decode


```solidity
function _decode(State memory s, Huffman memory h) private pure returns (ErrorCode, uint256);
```

### _construct


```solidity
function _construct(Huffman memory h, uint256[] memory lengths, uint256 n, uint256 start)
    private
    pure
    returns (ErrorCode);
```

### _codes


```solidity
function _codes(State memory s, Huffman memory lencode, Huffman memory distcode) private pure returns (ErrorCode);
```

### _build_fixed


```solidity
function _build_fixed(State memory s) private pure returns (ErrorCode);
```

### _fixed


```solidity
function _fixed(State memory s) private pure returns (ErrorCode);
```

### _build_dynamic_lengths


```solidity
function _build_dynamic_lengths(State memory s) private pure returns (ErrorCode, uint256[] memory);
```

### _build_dynamic


```solidity
function _build_dynamic(State memory s) private pure returns (ErrorCode, Huffman memory, Huffman memory);
```

### _dynamic


```solidity
function _dynamic(State memory s) private pure returns (ErrorCode);
```

### puff


```solidity
function puff(bytes memory source, uint256 destlen) internal pure returns (ErrorCode, bytes memory);
```

## Structs
### State

```solidity
struct State {
    //////////////////
    // Output state //
    //////////////////
    // Output buffer
    bytes output;
    // Bytes written to out so far
    uint256 outcnt;
    /////////////////
    // Input state //
    /////////////////
    // Input buffer
    bytes input;
    // Bytes read so far
    uint256 incnt;
    ////////////////
    // Temp state //
    ////////////////
    // Bit buffer
    uint256 bitbuf;
    // Number of bits in bit buffer
    uint256 bitcnt;
    //////////////////////////
    // Static Huffman codes //
    //////////////////////////
    Huffman lencode;
    Huffman distcode;
}
```

### Huffman

```solidity
struct Huffman {
    uint256[] counts;
    uint256[] symbols;
}
```

## Enums
### ErrorCode

```solidity
enum ErrorCode {
    ERR_NONE, // 0 successful inflate
    ERR_NOT_TERMINATED, // 1 available inflate data did not terminate
    ERR_OUTPUT_EXHAUSTED, // 2 output space exhausted before completing inflate
    ERR_INVALID_BLOCK_TYPE, // 3 invalid block type (type == 3)
    ERR_STORED_LENGTH_NO_MATCH, // 4 stored block length did not match one's complement
    ERR_TOO_MANY_LENGTH_OR_DISTANCE_CODES, // 5 dynamic block code description: too many length or distance codes
    ERR_CODE_LENGTHS_CODES_INCOMPLETE, // 6 dynamic block code description: code lengths codes incomplete
    ERR_REPEAT_NO_FIRST_LENGTH, // 7 dynamic block code description: repeat lengths with no first length
    ERR_REPEAT_MORE, // 8 dynamic block code description: repeat more than specified lengths
    ERR_INVALID_LITERAL_LENGTH_CODE_LENGTHS, // 9 dynamic block code description: invalid literal/length code lengths
    ERR_INVALID_DISTANCE_CODE_LENGTHS, // 10 dynamic block code description: invalid distance code lengths
    ERR_MISSING_END_OF_BLOCK, // 11 dynamic block code description: missing end-of-block code
    ERR_INVALID_LENGTH_OR_DISTANCE_CODE, // 12 invalid literal/length or distance code in fixed or dynamic block
    ERR_DISTANCE_TOO_FAR, // 13 distance is too far back in fixed or dynamic block
    ERR_CONSTRUCT // 14 internal: error in construct()
}
```

