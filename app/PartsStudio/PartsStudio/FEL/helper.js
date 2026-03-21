/* helper functions */
/* helper functions */
export var crc32 = (function()
{
    var table = new Uint32Array(256);

    // Pre-generate crc32 polynomial lookup table
    for(var i=256; i--;)
    {
        var tmp = i;

        for(var k=8; k--;)
        {
            tmp = tmp & 1 ? 3988292384 ^ tmp >>> 1 : tmp >>> 1;
        }

        table[i] = tmp;
    }

    // crc32b
    // Example input        : [97, 98, 99, 100, 101] (Uint8Array)
    // Example output       : 2240272485 (Uint32)
    return function( data )
    {
        var crc = -1; // Begin with all bits set ( 0xffffffff )

        for(var i=0, l=data.length; i<l; i++)
        {
            crc = crc >>> 8 ^ table[ crc & 255 ^ data[i] ];
        }

        return (crc ^ -1) >>> 0; // Apply binary NOT
    };

})();

export const sleep = ms => new Promise(r => setTimeout(r, ms));

export function concatenate(resultConstructor, ...arrays) {
	let totalLength = 0;
	for (const arr of arrays) {
        totalLength += arr.length;
    }
    const result = new resultConstructor(totalLength);
    let offset = 0;
    for (const arr of arrays) {
        result.set(arr, offset);
        offset += arr.length;
    }
    return result;
}