import Debug from 'debug';
import axios from 'axios';
import * as JSZip from 'jszip';
import { saveAs } from 'file-saver';
import {crc32, sleep, concatenate} from './helper.js';
//import * as spiflash from './spiflash.js';
/* Load SoC Info Table */
import soc_info_table from './soc_info_table.json';
//console.log("soc_info_table" + JSON.stringify(soc_info_table));

const debug=Debug('fel.js')

const cdb = axios.create();
let rax = require('retry-axios');

cdb.defaults.raxConfig = {
	instance: cdb,
	retry: 3,
	noResponseRetries: 10,
	retryDelay: 1000,
	onRetryAttempt: err => {
		const cfg = rax.getConfig(err);
		debug(`Retry attempt #${cfg.currentRetryAttempt}`);
	  }
};

const interceptorId = rax.attach(cdb);
debug (interceptorId);

const cdbURL = 'https://192.168.81.1/';

var dev_handle;
var uboot_entry;
var uboot_size;
var uploadedFiles = [];

const AW_USB_VENDOR_ID = 0x1F3A;
const AW_USB_PRODUCT_ID = 0xEFE8;

const DRAM_BASE = 0x40000000;
const DRAM_SIZE	= 0x80000000;

//FEL Commands
const AW_USB_READ = 0x11;
const AW_USB_WRITE = 0x12;

/* FEL request types */
const AW_FEL_VERSION = 0x001;
const AW_FEL_1_WRITE = 0x101;
const AW_FEL_1_EXEC = 0x102;
const AW_FEL_1_READ = 0x103;

/*
 * Maximum size of SPL, at the same time this is the start offset
 * of the main U-Boot image within u-boot-sunxi-with-spl.bin
 */
const SPL_LEN_LIMIT = 0x8000;
const SPL_SIGNATURE = "SPL";	/* marks "sunxi" header */
const SPL_MIN_VERSION = 1; 		/* minimum required version */
const SPL_MAX_VERSION = 2;	 	/* maximum supported version */

/* Constants taken from ${U-BOOT}/include/image.h */
const IH_MAGIC	= 0x27051956;	/* Image Magic Number	*/
const IH_ARCH_ARM =		2;		/* ARM			*/
const IH_TYPE_INVALID =		0;	/* Invalid Image	*/
const IH_TYPE_FIRMWARE =	5;	/* Firmware Image	*/
const IH_TYPE_SCRIPT =		6;	/* Script file		*/
const IH_NMLEN =		32;		/* Image Name Length	*/

/* Additional error codes, newly introduced for get_image_type() */
const IH_TYPE_ARCH_MISMATCH =	-1;

/*
 * Legacy format image U-Boot header,
 * all data in network byte order (aka natural aka bigendian).
 * Taken from ${U-BOOT}/include/image.h
 */
class image_header {
	constructor(header_buffer) {
		this.buffer = header_buffer;
		this.view = new DataView(this.buffer);
	}

	get ih_magic() {
		return this.view.getUint32(0);
	}

	get ih_hcrc() {
		return this.view.getUint32(4);
	}

	get ih_time() {
		return this.view.getUint32(8);
	}

	get ih_size() {
		return this.view.getUint32(12);
	}

	get ih_load() {
		return this.view.getUint32(16);
	}

	get ih_ep() {
		return this.view.getUint32(20);
	}

	get ih_dcrc() {
		return this.view.getUint32(24);
	}

	get ih_os() {
		return this.view.getUint8(28);
	}

	get ih_arch() {
		return this.view.getUint8(29);
	}

	get ih_type() {
		return this.view.getUint8(30);
	}

	get ih_comp() {
		return this.view.getUint8(31);
	}

	get ih_name() {
		var decoder = new TextDecoder('utf8');
		let name = decoder.decode(this.buffer.slice(IH_NMLEN, this.buffer.length)).replace(/[^\x20-\x7E]/g, '');
		return name;
	}

	get computed_hcrc() {
		/* The CRC is calculated on the whole header but the CRC itself */
		this.view.setUint32(4, 0);
		return crc32(Array.from(new Uint8Array(this.buffer)));
	}

	image_type(len) {
		if (len <= HEADER_SIZE)
			return IH_TYPE_INVALID;

		if(this.view.getUint32(0) !== IH_MAGIC)
			return IH_TYPE_INVALID;

		if(this.view.getUint8(29) !== IH_ARCH_ARM)
			return IH_TYPE_ARCH_MISMATCH;

		return this.view.getUint8(30);
	}

}

const HEADER_SIZE = 64;

/*
 * AW_USB_MAX_BULK_SEND and the timeout constant USB_TIMEOUT are related.
 * Both need to be selected in a way that transferring the maximum chunk size
 * with (SoC-specific) slow transfer speed won't time out.
 *
 * The 512 KiB here are chosen based on the assumption that we want a 10 seconds
 * timeout, and "slow" transfers take place at approx. 64 KiB/sec - so we can
 * expect the maximum chunk being transmitted within 8 seconds or less.
 */
const AW_USB_MAX_BULK_SEND = 512 * 1024; /* 512 KiB per bulk request */

/*
 * We don't want the scratch code/buffer to exceed a maximum size of 0x400 bytes
 * (256 32-bit words) on readl_n/writel_n transfers. To guarantee this, we have
 * to account for the amount of space the ARM code uses.
 */
const LCODE_ARM_WORDS = 12; /* word count of the [read/write]l_n scratch code */
const LCODE_ARM_SIZE =  (LCODE_ARM_WORDS << 2); /* code size in bytes */
const LCODE_MAX_TOTAL = 0x100; /* max. words in buffer */
const LCODE_MAX_WORDS = (LCODE_MAX_TOTAL - LCODE_ARM_WORDS); /* data words */

/*****************************************************************************/
// sram swap buffers

class sram_swap_buffers {
	constructor(buf1, buf2, size) {
		this.buffer = new ArrayBuffer(12);
		this.view = new DataView(this.buffer);
		this.view.setUint32(0, buf1, true);
		this.view.setUint32(4, buf2, true);
		this.view.setUint32(8, size, true);
	}

	/* BROM buffer */
	get buf1() {
		return this.view.getUint32(0, true);
	}

	/* backup storage location */
	get buf2() {
		return this.view.getUint32(4, true);
	}

	/* buffer size */
	get size() {
		return this.view.getUint32(8, true);
	}

	get length() {
		return this.buffer.byteLength;
	}

	get data() {
		return this.buffer;
	}

}

/*
 * The FEL code from BROM in A10/A13/A20 sets up two stacks for itself. One
 * at 0x2000 (and growing down) for the IRQ handler. And another one at 0x7000
 * (and also growing down) for the regular code. In order to use the whole
 * 32 KiB in the A1/A2 sections of SRAM, we need to temporarily move these
 * stacks elsewhere. And the addresses 0x7D00-0x7FFF contain something
 * important too (overwriting them kills FEL). On A10/A13/A20 we can use
 * the SRAM sections A3/A4 (0x8000-0xBFFF) for this purpose.
 */
const a10_a13_a20_sram_swap_buffers = [	new sram_swap_buffers(0x1C00, 0xA400, 0x0400),  /* 0x1C00-0x1FFF (IRQ stack) */
										new sram_swap_buffers(0x5C00, 0xA800, 0x1400),  /* 0x5C00-0x6FFF (Stack) */
										new sram_swap_buffers(0x7C00, 0xBC00, 0x0400)]; /* 0x7C00-0x7FFF (Something important) */

/*
 * A31 is very similar to A10/A13/A20, except that it has no SRAM at 0x8000.
 * So we use the SRAM section B at 0x20000-0x2FFFF instead. In the FEL mode,
 * the MMU translation table is allocated by the BROM at 0x20000. But we can
 * also safely use it as the backup storage because the MMU is temporarily
 * disabled during the time of the SPL execution.
 */
const a31_sram_swap_buffers = [	new sram_swap_buffers(0x1800, 0x20000, 0x800),
								new sram_swap_buffers(0x5C00, 0x20800, 0x8000 - 0x5C00 )];

/*
 * A64 has 32KiB of SRAM A at 0x10000 and a large SRAM C at 0x18000. SRAM A
 * and SRAM C reside in the address space back-to-back without any gaps, thus
 * representing a singe large contiguous area. Everything is the same as on
 * A10/A13/A20, but just shifted by 0x10000.
 */
const a64_sram_swap_buffers = [ new sram_swap_buffers(0x11C00, 0x1A400, 0x0400),  /* 0x11C00-0x11FFF (IRQ stack) */
								new sram_swap_buffers(0x15C00, 0x1A800, 0x1400),  /* 0x15C00-0x16FFF (Stack) */
								new sram_swap_buffers(0x17C00, 0x1BC00, 0x0400)]; /* 0x17C00-0x17FFF (Something important) */

/*								/*
 * Use the SRAM section at 0x44000 as the backup storage. This is the memory,
 * which is normally shared with the OpenRISC core (should we do an extra check
 * to ensure that this core is powered off and can't interfere?).
 */
const ar100_abusing_sram_swap_buffers = [	new sram_swap_buffers(0x1800, 0x44000, 0x800),
											new sram_swap_buffers(0x5C00, 0x44800, 0x8000 - 0x5C00 )];

/*
 * A80 has 40KiB SRAM A1 at 0x10000 where the SPL has to be loaded to. The
 * secure SRAM B at 0x20000 is used as backup area for FEL stacks and data.
 */
const a80_sram_swap_buffers = [	new sram_swap_buffers(0x11800, 0x20000, 0x800),
								new sram_swap_buffers(0x15400, 0x20800, 0x18000 - 0x15400 )];

/*
 * H6 has 32KiB of SRAM A at 0x20000 and a large SRAM C at 0x28000. SRAM A
 * and SRAM C reside in the address space back-to-back without any gaps, thus
 * representing a singe large contiguous area. Everything is the same as on
 * A10/A13/A20, but just shifted by 0x20000.
 */
const h6_sram_swap_buffers = [	new sram_swap_buffers(0x21C00, 0x2A400, 0x0400),  /* 0x21C00-0x21FFF (IRQ stack) */
								new sram_swap_buffers(0x25C00, 0x2A800, 0x1400),  /* 0x25C00-0x26FFF (Stack) */
								new sram_swap_buffers(0x27C00, 0x2BC00, 0x0400)]; /* 0x27C00-0x27FFF (Something important) */

const swap_buffers_array = { 	a10_a13_a20_sram_swap_buffers,
								a31_sram_swap_buffers,
								a64_sram_swap_buffers,
								ar100_abusing_sram_swap_buffers,
								a80_sram_swap_buffers,
								h6_sram_swap_buffers
							};

/*****************************************************************************/

class fel_to_spl_thunk {
	constructor() {
		this.buffer = new ArrayBuffer(264);
		this.view = new DataView(this.buffer);
		this.view.setUint32(0, 0xea000015, true); 	/*        0:    b          5c <setup_stack>             */
		/* <stack_begin>: */
		this.view.setUint32(4, 0xe1a00000, true); 	/*        4:    nop                                     */
		this.view.setUint32(8, 0xe1a00000, true); 	/*        8:    nop                                     */
		this.view.setUint32(12, 0xe1a00000, true); 	/*        c:    nop                                     */
		this.view.setUint32(16, 0xe1a00000, true); 	/*       10:    nop                                     */
		this.view.setUint32(20, 0xe1a00000, true); 	/*       14:    nop                                     */
		this.view.setUint32(24, 0xe1a00000, true); 	/*       18:    nop                                     */
		this.view.setUint32(28, 0xe1a00000, true); 	/*       1c:    nop                                     */
		this.view.setUint32(32, 0xe1a00000, true); 	/*       20:    nop                                     */
		/* <stack_end>: */
		this.view.setUint32(36, 0xe1a00000, true); 	/*       24:    nop                                     */
		/* <swap_all_buffers>: */
		this.view.setUint32(40, 0xe28f40dc, true); 	/*       28:    add        r4, pc, #220                 */
		/* <swap_next_buffer>: */
		this.view.setUint32(44, 0xe4940004, true); 	/*       2c:    ldr        r0, [r4], #4                 */
		this.view.setUint32(48, 0xe4941004, true); 	/*       30:    ldr        r1, [r4], #4                 */
		this.view.setUint32(52, 0xe4946004, true); 	/*       34:    ldr        r6, [r4], #4                 */
		this.view.setUint32(56, 0xe3560000, true); 	/*       38:    cmp        r6, #0                       */
		this.view.setUint32(60, 0x012fff1e, true); 	/*       3c:    bxeq       lr                           */
		/* <swap_next_word>: */
		this.view.setUint32(64, 0xe5902000, true); 	/*       40:    ldr        r2, [r0]                     */
		this.view.setUint32(68, 0xe5913000, true); 	/*       44:    ldr        r3, [r1]                     */
		this.view.setUint32(72, 0xe2566004, true); 	/*       48:    subs       r6, r6, #4                   */
		this.view.setUint32(76, 0xe4812004, true); 	/*       4c:    str        r2, [r1], #4                 */
		this.view.setUint32(80, 0xe4803004, true); 	/*       50:    str        r3, [r0], #4                 */
		this.view.setUint32(84, 0x1afffff9, true); 	/*       54:    bne        40 <swap_next_word>          */
		this.view.setUint32(88, 0xeafffff3, true); 	/*       58:    b          2c <swap_next_buffer>        */
		/* <setup_stack>: */
		this.view.setUint32(92, 0xe59f80a4, true); 	/*       5c:    ldr        r8, [pc, #164]               */
		this.view.setUint32(96, 0xe24f0044, true); 	/*       60:    sub        r0, pc, #68                  */
		this.view.setUint32(100, 0xe520d004, true); /*       64:    str        sp, [r0, #-4]!               */
		this.view.setUint32(104, 0xe1a0d000, true); /*       68:    mov        sp, r0                       */
		this.view.setUint32(108, 0xe10f2000, true); /*       6c:    mrs        r2, CPSR                     */
		this.view.setUint32(112, 0xe92d4004, true); /*       70:    push       {r2, lr}                     */
		this.view.setUint32(116, 0xe38220c0, true); /*       74:    orr        r2, r2, #192                 */
		this.view.setUint32(120, 0xe121f002, true); /*       78:    msr        CPSR_c, r2                   */
		this.view.setUint32(124, 0xee112f10, true); /*       7c:    mrc        15, 0, r2, cr1, cr0, {0}     */
		this.view.setUint32(128, 0xe3013004, true); /*       80:    movw       r3, #4100                    */
		this.view.setUint32(132, 0xe1120003, true); /*       84:    tst        r2, r3                       */
		this.view.setUint32(136, 0x1a000012, true); /*       88:    bne        d8 <cache_is_unsupported>    */
		this.view.setUint32(140, 0xebffffe5, true); /*       8c:    bl         28 <swap_all_buffers>        */
		/* <verify_checksum>: */
		this.view.setUint32(144, 0xe3067c39, true); /*       90:    movw       r7, #27705                   */
		this.view.setUint32(148, 0xe3457f0a, true); /*       94:    movt       r7, #24330                   */
		this.view.setUint32(152, 0xe1a00008, true); /*       98:    mov        r0, r8                       */
		this.view.setUint32(156, 0xe5905010, true); /*       9c:    ldr        r5, [r0, #16]                */
		/* <check_next_word>: */
		this.view.setUint32(160, 0xe4902004, true); /*       a0:    ldr        r2, [r0], #4                 */
		this.view.setUint32(164, 0xe2555004, true); /*       a4:    subs       r5, r5, #4                   */
		this.view.setUint32(168, 0xe0877002, true); /*       a8:    add        r7, r7, r2                   */
		this.view.setUint32(172, 0x1afffffb, true); /*       ac:    bne        a0 <check_next_word>         */
		this.view.setUint32(176, 0xe598200c, true); /*       b0:    ldr        r2, [r8, #12]                */
		this.view.setUint32(180, 0xe0577082, true); /*       b4:    subs       r7, r7, r2, lsl #1           */
		this.view.setUint32(184, 0x1a00000a, true); /*       b8:    bne        e8 <checksum_is_bad>         */
		this.view.setUint32(188, 0xe304262e, true); /*       bc:    movw       r2, #17966                   */
		this.view.setUint32(192, 0xe3442c45, true); /*       c0:    movt       r2, #19525                   */
		this.view.setUint32(196, 0xe5882008, true); /*       c4:    str        r2, [r8, #8]                 */
		this.view.setUint32(200, 0xf57ff04f, true); /*       c8:    dsb        sy                           */
		this.view.setUint32(204, 0xf57ff06f, true); /*       cc:    isb        sy                           */
		this.view.setUint32(208, 0xe12fff38, true); /*       d0:    blx        r8                           */
		this.view.setUint32(212, 0xea000006, true); /*       d4:    b          f4 <return_to_fel>           */
		/* <cache_is_unsupported>: */
		this.view.setUint32(216, 0xe3032f2e, true); /*       d8:    movw       r2, #16174                   */
		this.view.setUint32(220, 0xe3432f3f, true); /*       dc:    movt       r2, #16191                   */
		this.view.setUint32(224, 0xe5882008, true); /*       e0:    str        r2, [r8, #8]                 */
		this.view.setUint32(228, 0xea000003, true); /*       e4:    b          f8 <return_to_fel_noswap>    */
		/* <checksum_is_bad>: */
		this.view.setUint32(232, 0xe304222e, true); /*       e8:    movw       r2, #16942                   */
		this.view.setUint32(236, 0xe3442441, true); /*       ec:    movt       r2, #17473                   */
		this.view.setUint32(240, 0xe5882008, true); /*       f0:    str        r2, [r8, #8]                 */
		/* <return_to_fel>: */
		this.view.setUint32(244, 0xebffffcb, true); /*       f4:    bl         28 <swap_all_buffers>        */
		/* <return_to_fel_noswap>: */
		this.view.setUint32(248, 0xe8bd4004, true); /*       f8:    pop        {r2, lr}                     */
		this.view.setUint32(252, 0xe121f002, true); /*       fc:    msr        CPSR_c, r2                   */
		this.view.setUint32(256, 0xe59dd000, true); /*      100:    ldr        sp, [sp]                     */
		this.view.setUint32(260, 0xe12fff1e, true); /*      104:    bx         lr                           */
	}

	get data() {
		return this.buffer;
	}

	get length() {
		return this.buffer.byteLength;
	}
}

function get_soc_name_from_id(id) {
	return soc_info_table[id].name;
}

/* function get_soc_info_from_version() {} */

function get_soc_info_from_id(id) {
	var soc_info = new soc_info_t();
	let info_table = soc_info_table[id];

	soc_info.soc_id = info_table.soc_id;

	soc_info.name = info_table.name;

	if(info_table.hasOwnProperty('spl_addr'))
		soc_info.spl_addr = info_table.spl_addr;

	soc_info.scratch_addr = info_table.scratch_addr;

	soc_info.thunk_addr = info_table.thunk_addr;

	soc_info.thunk_size = info_table.thunk_size;

	if(info_table.hasOwnProperty('needs_l2en'))
		soc_info.needs_l2en = info_table.needs_l2en;
	else
		soc_info.needs_l2en = false;

	if(info_table.hasOwnProperty('mmu_tt_addr'))
		soc_info.mmu_tt_addr = info_table.mmu_tt_addr;

	if(info_table.hasOwnProperty('sid_base'))
		soc_info.sid_base = info_table.sid_base;

	if(info_table.hasOwnProperty('sid_offset'))
		soc_info.sid_offset = info_table.sid_offset;

	if(info_table.hasOwnProperty('rvbar_reg'))
		soc_info.rvbar_reg = info_table.rvbar_reg;

	if(info_table.hasOwnProperty('sid_fix'))
		soc_info.sid_fix = info_table.sid_fix;

	if(info_table.hasOwnProperty('needs_smc_workaround_if_zero_word_at_addr'))
		soc_info.needs_smc_workaround_if_zero_word_at_addr = info_table.needs_smc_workaround_if_zero_word_at_addr;

	soc_info.swap_buffers = swap_buffers_array[info_table.swap_buffers];

	return soc_info;
}

class soc_info_t {
	constructor() {
		this.id = 0;        /* ID of the SoC */
		this.name = "";      /* human-readable SoC name string */
		this.spl_address = 0;      /* SPL load address */
		this.scratch_address = 0;  /* A safe place to upload & run code */
		this.thunk_address = 0;    /* Address of the thunk code */
		this.thunk_code_size = 0;    /* Maximal size of the thunk code */
		this.l2en = Boolean(false);   /* Set the L2EN bit */
		this.mmu_tt_address = 0;   /* MMU translation table address */
		this.sid_base_addr = 0;      /* base address for SID registers */
		this.sid_offset_n = 0;    /* offset for SID_KEY[0-3], "root key" */
		this.rvbar_register = 0;     /* MMIO address of RVBARADDR0_L register */
		this.id_fix = Boolean(false);      /* Use SID workaround (read via register) */
		/* Use SMC workaround (enter secure mode) if can't read from this address */
		this.needs_smc_workaround_if_zero_word_at_address = 0;
		this.swap_buffers_array = [];
	}

	get soc_id ()
	{
		return this.id;
	}

	set soc_id(id) {
		this.id = id;
	}

	get soc_name () {
		return this.name;
	}

	set soc_name(name) {
		this.name = name;
	}

	get spl_addr() {
		return this.spl_address;
	}

	set spl_addr(addr) {
		this.spl_address = Number(addr);
	}

	get sid_base() {
		return this.sid_base_addr;
	}

	set sid_base(addr) {
		this.sid_base_addr = Number(addr);
	}

	get sid_offset() {
		return this.sid_offset_n;
	}

	set sid_offset(offset) {
		this.sid_offset_n = Number(offset);
	}

	get sid_fix() {
		return this.id_fix;
	}

	set sid_fix(value) {
		this.id_fix = Boolean(value); 
	}

	get scratch_addr() {
		return this.scratch_address;
	}

	set scratch_addr(addr) {
		this.scratch_address = Number(addr);
	}

	get mmu_tt_addr() {
		return this.mmu_tt_address;
	}

	set mmu_tt_addr(addr) {
		this.mmu_tt_address = addr;
	}

	get swap_buffers() {
		return this.swap_buffers_array;
	}

	set swap_buffers(buffers) {
		this.swap_buffers_array = buffers;
	}

	get swap_buffers_size() {
		var size = 0;;
		for (var i = 0; i < this.swap_buffers_array.length; i++)
		{
			size += this.swap_buffers_array[i].length;
		}
		return size;
	}

	get thunk_addr() {
		return this.thunk_address;
	}

	set thunk_addr(addr) {
		this.thunk_address = Number(addr);
	}

	get thunk_size() {
		return this.thunk_code_size;
	}

	set thunk_size(size) {
		this.thunk_code_size = Number(size);
	}

	get needs_l2en() {
		return this.l2en;
	}

	set needs_l2en(value) {
		this.l2en = Boolean(value);
	}

	get rvbar_reg() {
		return this.rvbar_register;
	}

	set rvbar_reg(addr) {
		this.rvbar_register = Number(addr);
	}

	get needs_smc_workaround_if_zero_word_at_addr() {
		return this.needs_smc_workaround_if_zero_word_at_address;
	}

	set needs_smc_workaround_if_zero_word_at_addr(addr) {
		this.needs_smc_workaround_if_zero_word_at_address = Number(addr);
	}
}

class feldev_handle {
	constructor(usbDevice) {
		this.device = usbDevice;
		this.soc_version = 0;
		this.soc_name = "";
		this.soc_info = new soc_info_t();
	}

}

class aw_fel_request  {
	constructor (request, address, length) {
		this.buffer = new ArrayBuffer(16);
		this.view = new DataView(this.buffer);
		this.view.setUint32(0, request, true);
		this.view.setUint32(4, address, true);
		this.view.setUint32(8, length, true);
		//this.pad
	}

	get data() {
		return this.buffer;
	}

	get length() {
		return this.buffer.byteLength;
	}

}

class aw_usb_request {
	constructor(request, length) {
		this.buffer = new ArrayBuffer(32);
		this.view = new DataView(this.buffer);
		this.view.setUint32(0, 0x41575543, false);	//"AWUC";
		this.view.setUint32(8, length, true);		//length
		this.view.setUint8(15, 0x0C);				//unknown1
		this.view.setUint16(16, request, true);		//request
		this.view.setUint32(18, length, true);		//length2
	}

	get data() {
		return this.buffer;
	}


}

class aw_fel_version {
	constructor(view) {
		this.view = view;
	}

	get signature() {
		return String.fromCharCode(this.view.getUint8(0), this.view.getUint8(1), this.view.getUint8(2), this.view.getUint8(3), this.view.getUint8(4), this.view.getUint8(5), this.view.getUint8(6), this.view.getUint8(7));
	}

	get soc_id() {
		let word = this.view.getUint32(8, true) >> 8;
		return word.toString(16);
	}

	get unknown_0a() {
		return this.view.getUint32(12, true);
	}

	get protocol() {
		return this.view.getUint16(16, true).toString(16);
	}

	get unknown_12() {
		return this.view.getUint8(18, true).toString(16);
	}

	get unknown_13() {
		return this.view.getUint8(19, true).toString(16);
	}

	get scratchpad() {
		return this.view.getUint32(20, true).toString(16);
	}

	get pad0() {
		return this.view.getUint32(24, true).toString(16);
	}

	get pad1() {
		return this.view.getUint32(28, true).toString(16);
	}
		/* ... */

	toString() {
		return (this.signature + " soc=" + this.soc_id + "(" + dev_handle.soc_name + ") " +
				this.unknown_0a + " ver=" + this.protocol + " " + this.unknown_12 +
				" " + this.unknown_13 + " scratchpad=" + this.scratchpad + " " +
				this.pad0 + " " + this.pad1);
	}
}

async function usb_bulk_send(data, ep) {
	var max_chunk = AW_USB_MAX_BULK_SEND;

	if (data !== undefined) {
		var chunk = data.byteLength < max_chunk ? data.byteLength : max_chunk;
		var index = 0;
		var length = data.byteLength;
		while (length > 0) {
			await dev_handle.device.transferOut(ep, data.slice(index, index + chunk));
			length -= chunk;
			index += chunk;
		}

		return Promise.resolve("Sucessfully wrote data");
	} else {
		return Promise.reject("data is undefined");
	}
}

async function usb_bulk_recv(length, ep) {
	return await dev_handle.device.transferIn(ep, length);
}

async function aw_send_usb_request(type, length) {
	var req = new aw_usb_request(type, length);
    var ep = dev_handle.device.configuration.interfaces[0].alternate.endpoints[0].endpointNumber;
	return await usb_bulk_send(req.data, ep);
}

async function aw_read_usb_response(length) {
	var ep  = dev_handle.device.configuration.interfaces[0].alternate.endpoints[1].endpointNumber;
	return await usb_bulk_recv(length, ep);
}

async function aw_usb_write(data, length) {
	var ep  = dev_handle.device.configuration.interfaces[0].alternate.endpoints[0].endpointNumber;
	try {
		await aw_send_usb_request(AW_USB_WRITE, length);
		await usb_bulk_send(data, ep);
		await aw_read_usb_response(13);
	} catch (e) {
		throw e;
	}
}

async function aw_usb_read(length) {
	try {
		await aw_send_usb_request(AW_USB_READ, length);
		let response = await aw_read_usb_response(length);
		await aw_read_usb_response(13); 
		return response;
	} catch(e) { 
		throw e;
	}
}

async function aw_send_fel_request(type, addr, length)
{
	var req = new aw_fel_request(type, addr, length);
	return await aw_usb_write(req.data, req.length); 
}

async function aw_read_fel_status() {
	return await aw_usb_read(8);
}

async function aw_fel_get_version() {
	try {
		await aw_send_fel_request(AW_FEL_VERSION, 0, 0);
		let result = await aw_usb_read(32);
		await aw_read_fel_status();
		dev_handle.soc_version = new aw_fel_version(result.data);
	} catch(e) {
		throw e;
	}
}

function aw_fel_print_version(result) {

	if( !dev_handle.soc_name || dev_handle.soc_name.trim().length === 0)
		dev_handle.soc_name = "unknown";

	//print
	debug(dev_handle.soc_version);
	document.getElementById("versionResult").innerHTML = "Version: " + dev_handle.soc_version;
}

async function aw_fel_print_sid() {
	//check sid registers for your SoC are  unknown or inaccessible


	try {
		let ID = await fel_get_sid_root_key();
		var parsedID = "";
		for(var i = 0; i <= 3; i++)
		{
			parsedID = parsedID.concat(ID[i].toString(16));
			if (i < 3) 
				parsedID = parsedID.concat(':');
		}
		debug(parsedID);
		document.getElementById("serialIDResult").innerHTML = "SID: " + parsedID;

		// TODO: enable when api.source.parts/v1/devices endpoint exists
		// let DEVICE_API_URL='https://api.source.parts/v1/devices/';
		// await cdb.get(DEVICE_API_URL + parsedID)
	} catch(e) {
		throw e;
	}
}

async function fel_get_sid_root_key(force_workaround) {
	// check base (SID unavailable)
	if (dev_handle.soc_info.sid_base === 0)
	{
		return new Uint32Array(4);
	}

	if(dev_handle.soc_info.sid_fix === true || force_workaround) {
		/* Work around SID issues by using ARM thunk code */
		try {
			let sid = await fel_get_sid_registers();
			return sid;
		} catch(e) {
			throw e;
		}
	}
	else {
		/* Read SID directly from memory */
		try {
			let sid = await fel_readl_n(dev_handle.soc_info.sid_base + dev_handle.soc_info.sid_offset, 4);
			return sid;
		} catch(e) {
			throw e;
		}
	}
}

async function fel_get_sid_registers()
{
	let soc_info = dev_handle.soc_info;

	var arm_code = new ArrayBuffer(76);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe59f0040, true); 					/*    0:  ldr   r0, [pc, #64]           */
	view.setUint32(4, 0xe3a01000, true);					/*    4:  mov   r1, #0                  */
	view.setUint32(8, 0xe28f303c, true);					/*    8:  add   r3, pc, #60             */
	/* <sid_read_loop>: */
	view.setUint32(12, 0xe1a02801, true);					/*    c:  lsl   r2, r1, #16             */
	view.setUint32(16, 0xe3822b2b, true);					/*   10:  orr   r2, r2, #44032          */
	view.setUint32(20, 0xe3822002, true);					/*   14:  orr   r2, r2, #2              */
	view.setUint32(24, 0xe5802040, true);					/*   18:  str   r2, [r0, #64]           */
	/* <sid_read_wait>: */
	view.setUint32(28, 0xe5902040, true);					/*   1c:  ldr   r2, [r0, #64]           */
	view.setUint32(32, 0xe3120002, true);					/*   20:  tst   r2, #2                  */
	view.setUint32(36, 0x1afffffc, true);					/*   24:  bne   1c <sid_read_wait>      */
	view.setUint32(40, 0xe5902060, true); 					/*   28:  ldr   r2, [r0, #96]           */
	view.setUint32(44, 0xe7832001, true); 					/*   2c:  str   r2, [r3, r1]            */
	view.setUint32(48, 0xe2811004, true); 					/*   30:  add   r1, r1, #4              */
	view.setUint32(52, 0xe3510010, true); 					/*   34:  cmp   r1, #16                 */
	view.setUint32(56, 0x3afffff3, true); 					/*   38:  bcc   c <sid_read_loop>       */
	view.setUint32(60, 0xe3a02000, true); 					/*   3c:  mov   r2, #0                  */
	view.setUint32(64, 0xe5802040, true); 					/*   40:  str   r2, [r0, #64]           */
	view.setUint32(68, 0xe12fff1e, true); 					/*   44:  bx    lr                      */
	view.setUint32(72, dev_handle.soc_info.sid_base, true); 					/* SID base addr */
	/* retrieved SID values go here */

	/* write and execute code */
	await aw_fel_write(arm_code, soc_info.scratch_addr, 76);
	await aw_fel_execute(soc_info.scratch_addr);
	/* read back the result */
	let response = await aw_fel_read(soc_info.scratch_addr + 76, 16);
	view = new DataView(response.data.buffer);
	var result = new Uint32Array();
	var i = 0;
	var length = 16;
	while (length > i)
	{
		result = concatenate(Uint32Array, result, Uint32Array.of(view.getUint32(i, true)));
		i += 4;
	}
	return result;
}

/* "writel" of a single value */
async function fel_writel(addr, val)
{
	let buf = new ArrayBuffer(4);
	let view = new DataView(buf);
	view.setUint32(0, val, true);
	await aw_fel_write(buf, addr, 4);
}

async function fel_writel_n() {
	// TODO: batch write via ARM thunk
}

async function aw_fel_writel_n() {
	// TODO: batch write via ARM thunk
}

/* "readl" of a single value */
async function fel_readl(addr)
{
	let result = await aw_fel_read(addr, 4);
	// aw_fel_read returns a USBInTransferResult, extract the buffer
	let buf = result.data ? result.data.buffer : result;
	let view = new DataView(buf);
	return view.getUint32(0, true);
}

/*
 * aw_fel_readl_n() wrapper that can handle large transfers. If necessary,
 * those will be done in separate 'chunks' of no more than LCODE_MAX_WORDS.
 */
async function fel_readl_n(addr, count) {
	var buffer = new Uint32Array();

	while(count > 0) {
			let n = count > LCODE_ARM_WORDS ? LCODE_MAX_WORDS : count;
			try {
				let words = await aw_fel_readl_n(addr, n);
				buffer = concatenate(Uint32Array, buffer, words);
				addr += n * 4;
				count -= n;
			} catch (e) {
				throw e;
			}
	}
	return buffer;
}

/* multiple "readl" from sequential addresses to a destination buffer */
async function aw_fel_readl_n(addr, count) {
	if(count === 0) return;
	if(count > LCODE_MAX_WORDS) {
		debug("ERROR: Max. word count exceeded, truncating aw_fel_readl_n() transfer");
		count = LCODE_MAX_WORDS;
	}
	//assert(LCODE_MAX_WORDS < 256);  /* protect against corruption of ARM code */
	var arm_code = new ArrayBuffer(48);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe59f0020, true); 					/* ldr  r0, [pc, #32] ; ldr r0,[read_addr]  */
	view.setUint32(4, 0xe28f1024, true);					/* add  r1, pc, #36   ; adr r1, read_data   */
	view.setUint32(8, 0xe59f201c, true);					/* ldr  r2, [pc, #28] ; ldr r2,[read_count] */
	view.setUint32(12, 0xe3520000 + LCODE_MAX_WORDS, true);	/* cmp	r2, #LCODE_MAX_WORDS */
	view.setUint32(16, 0xc3a02000 + LCODE_MAX_WORDS, true);	/* movgt	r2, #LCODE_MAX_WORDS */
	/* read_loop: */
	view.setUint32(20, 0xe2522001, true);					/* subs r2, r2, #1    ; r2 -= 1             */
	view.setUint32(24, 0x412fff1e, true);					/* bxmi lr            ; return if (r2 < 0)  */
	view.setUint32(28, 0xe4903004, true);					/* ldr  r3, [r0], #4  ; load and post-inc   */
	view.setUint32(32, 0xe4813004, true);					/* str  r3, [r1], #4  ; store and post-inc  */
	view.setUint32(36, 0xeafffffa, true);					/* b    read_loop  							*/
	view.setUint32(40, addr, true);							/* read_addr */
	view.setUint32(44, count, true);						/* read_count */
	/* read_data (buffer) follows, i.e. values go here */

	//assert(sizeof(arm_code) == LCODE_ARM_SIZE);

	/* scratch buffer setup: transfers ARM code, including addr and count */
	try {
		await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 48);
		await aw_fel_execute(dev_handle.soc_info.scratch_addr);
		let response = await aw_fel_read((dev_handle.soc_info.scratch_addr + LCODE_ARM_SIZE), count * 4);
		/* extract values to destination buffer */
		var buffer = response.data.buffer;
		view = new DataView(buffer);
		var result = new Uint32Array();
		var i = 0;
		var length = count * 4;
		while (count-- > 0 && length > i)
		{
			result = concatenate(Uint32Array, result, Uint32Array.of(view.getUint32(i, true)));
			i += 4;
		}
		return result;

	} catch (e) {
		throw e;
	}
}

/* AW_FEL_1_WRITE request */
async function aw_fel_write(buffer, offset, len) {
	try {
		await aw_send_fel_request(AW_FEL_1_WRITE, offset, len);
		await aw_usb_write(buffer, len);
		await aw_read_fel_status();
	} catch(e) { 
		throw e;
	}
}

/*
 * This function is a higher-level wrapper for the FEL write functionality.
 * Unlike aw_fel_write() above - which is reserved for internal use - this
 * routine optionally allows progress callbacks.
 */
async function aw_fel_write_buffer(buffer, offset, len) {
	try {
		await aw_send_fel_request(AW_FEL_1_WRITE, offset, len);
		await aw_usb_write(buffer, len);
		await aw_read_fel_status();
	} catch(e) {
		throw e;
	}
}

/* AW_FEL_1_EXEC request */
async function aw_fel_execute(offset) {
	try {
		await aw_send_fel_request(AW_FEL_1_EXEC, offset, 0);
		await aw_read_fel_status();
	} catch(e) { 
		throw e;
	}
}

/* AW_FEL_1_READ request */
async function aw_fel_read(offset, len)
{
	try {
		await aw_send_fel_request(AW_FEL_1_READ, offset, len);
		let response = await aw_usb_read(len);
		await aw_read_fel_status(); 
		return response;
	} catch(e) { 
		throw e;
	}
}

async function aw_fel_process_spl_and_uboot()
{
	var i;
	var ubootData = null;
	/* load file into memory buffer */
	for (i in uploadedFiles)
	{
		if((uploadedFiles[i].name === "u-boot-sunxi-with-spl.bin") || (uploadedFiles[i].name === "sunxi-a64-spl32-ddr3.bin"))
		{
			ubootData = uploadedFiles[i].data;
			break;
		}
	}

	if(ubootData == null)
		return;

	var size = ubootData.byteLength;

	/* write and execute the SPL from the buffer */
	await aw_fel_write_and_execute_spl(ubootData, size);
	/* check for optional main U-Boot binary (and transfer it, if applicable) */
	if (size > SPL_LEN_LIMIT)
		return await aw_fel_write_uboot_image(ubootData.slice(SPL_LEN_LIMIT, size), size - SPL_LEN_LIMIT);
}

async function aw_fel_write_and_execute_spl(buffer, len)
{
	var view = new DataView(buffer);
	var soc_info = dev_handle.soc_info;
	var tt = null;
	var swap_buffers = [];
	var spl_checksum, spl_len, spl_len_limit = SPL_LEN_LIMIT;
	var cur_addr = soc_info.spl_addr;
	var thunk_size;
	var i = 0;
	var fel_to_spl_thunk_code = new fel_to_spl_thunk();
	var decoder = new TextDecoder('utf8');

	if (!soc_info || !soc_info.swap_buffers)
		throw Error("SPL: Unsupported SoC type");
	
	var spl_egon = buffer.slice(4, 12);
	let spl_egon_string = decoder.decode(spl_egon);

	if (len < 32 || "eGON.BT0" !== spl_egon_string)
		throw Error("SPL: eGON header is not found");

	spl_checksum = 2 * view.getUint32(12, true) - 0x5F0A6C39 >>> 0;
	spl_len = view.getUint32(16, true);

	if (spl_len > len || (spl_len % 4) !== 0)
		throw Error("SPL: bad length in the eGON header");

	len = spl_len;
	for (i = 0; i < len; i+=4)
	{
		spl_checksum -= view.getUint32(i, true);
		spl_checksum = spl_checksum >>> 0;
	}

	if (spl_checksum !== 0) {
		throw Error("SPL: checksum check failed");
	}

	if (soc_info.needs_l2en === true) {
		//debug("Enabling the L2 cache");
		await aw_enable_l2_cache();
	}

	let result = await aw_get_stackinfo();
	var sp_irq = result[0];
	var sp = result[1];
	//debug("Stack pointers: sp_irq=" + sp_irq.toString(16) + ", sp=" + sp.toString(16))

	var tt = await aw_backup_and_disable_mmu();

	if (!tt && soc_info.mmu_tt_addr) {
		if (soc_info.mmu_tt_addr & 0x3FFF)
			throw Error("SPL: 'mmu_tt_addr' must be 16K aligned");

		//debug("Generating the new MMU translation table at 0x" +
		//			soc_info.mmu_tt_addr.toString(16));
		/*
		 * These settings are used by the BROM in A10/A13/A20 and
		 * we replicate them here when enabling the MMU. The DACR
		 * value 0x55555555 means that accesses are checked against
		 * the permission bits in the translation tables for all
		 * domains. The TTBCR value 0x00000000 means that the short
		 * descriptor translation table format is used, TTBR0 is used
		 * for all the possible virtual addresses (N=0) and that the
		 * translation table must be aligned at a 16K boundary.
		 */
		await aw_set_dacr(0x55555555);
		await aw_set_ttbcr(0x00000000);
		await aw_set_ttbr0(soc_info.mmu_tt_addr);
		tt = aw_generate_mmu_translation_table();
	}
	
	var buf = 0;
	swap_buffers = soc_info.swap_buffers;
	for (i = 0; i < swap_buffers.length; i++) {
		if ((swap_buffers[i].buf2 >= soc_info.spl_addr) &&
		    (swap_buffers[i].buf2 < soc_info.spl_addr + spl_len_limit))
			spl_len_limit = swap_buffers[i].buf2 - soc_info.spl_addr;
		if (len > 0 && cur_addr < swap_buffers[i].buf1) {
			var tmp = swap_buffers[i].buf1 - cur_addr;
			if (tmp > len)
				tmp = len;
			await aw_fel_write(buffer.slice(buf, buf+tmp), cur_addr, tmp);
			cur_addr += tmp;
			buf += tmp;
			len -= tmp;
		}
		if (len > 0 && cur_addr === swap_buffers[i].buf1) {
			var tmp = swap_buffers[i].size;
			if (tmp > len)
				tmp = len;
			await aw_fel_write(buffer.slice(buf, buf+tmp), swap_buffers[i].buf2, tmp);
			cur_addr += tmp;
			buf += tmp;
			len -= tmp;
		}
	}

	// Clarify the SPL size limitations, and bail out if they are not met 
	if (soc_info.thunk_addr < spl_len_limit)
		spl_len_limit = soc_info.thunk_addr;

	if (spl_len > spl_len_limit)
		throw Error("SPL: too large (need " +
			 spl_len.toString() + ", have " + spl_len_limit.toString());

	// Write the remaining part of the SPL
	if (len > 0)
		await aw_fel_write(buffer, cur_addr, len);

	thunk_size = fel_to_spl_thunk_code.length + 4 +
			 (i + 1) * soc_info.swap_buffers_size;
			 

	if (thunk_size > soc_info.thunk_size) {
		throw Error("SPL: bad thunk size (need " + fel_to_spl_thunk_code.length + ", have " +
			 		soc_info.thunk_size);
	}
	
	var thunk_buf = new ArrayBuffer(thunk_size);
	var thunk_view = new DataView(thunk_buf);

	new Uint8Array(thunk_buf).set(new Uint8Array(fel_to_spl_thunk_code.data));
	
	thunk_view.setUint32(fel_to_spl_thunk_code.length, soc_info.spl_addr, true);

	var buf_count;
	var buf_offset = fel_to_spl_thunk_code.length + 4;
	for (buf_count = 0; buf_count < swap_buffers.length; buf_count++)
	{
		new Uint8Array(thunk_buf).set(new Uint8Array(swap_buffers[buf_count].data), buf_offset);
		buf_offset += swap_buffers[buf_count].length;
	}

	debug("=> Executing the SPL...");
	await aw_fel_write(thunk_buf, soc_info.thunk_addr, thunk_size);
	await aw_fel_execute(soc_info.thunk_addr);
	debug("done");

	/* TODO: Try to find and fix the bug, which needs this workaround */
	sleep(250);

	/* Read back the result and check if everything was fine */
	let response = await aw_fel_read(dev_handle.soc_info.spl_addr + 4, 8);
	let responseString = decoder.decode(response.data);
	if ("eGON.FEL" !== responseString)
		throw Error("SPL: failure code " + responseString);

	if(tt !== null)
		await aw_restore_and_enable_mmu(tt);
}

/*
 * This function tests a given buffer address and length for a valid U-Boot
 * image. Upon success, the image data gets transferred to the default memory
 * address stored within the image header; and the function preserves the
 * U-Boot entry point (offset) and size values.
 */
async function aw_fel_write_uboot_image(buffer, len)
{
	if(len <= HEADER_SIZE)
		return;

	var hdr = new image_header(buffer.slice(0, HEADER_SIZE));

	var hcrc = hdr.ih_hcrc;
	let computed_hcrc = hdr.computed_hcrc;

	if(hcrc !== computed_hcrc)
	{
		throw Error("U-Boot header CRC mismatch: expected " + hcrc.toString(16) +
					", got " + computed_hcrc.toString(16));
	}

	/* Check for a valid mkimage header */
	let image_type = hdr.image_type(len);
	if (image_type <= IH_TYPE_INVALID) {
		switch(image_type) {
			case IH_TYPE_INVALID: {
				throw Error("Invalid U-Boot image: bad size or signature");
			}
			case IH_TYPE_ARCH_MISMATCH: {
				throw Error("Invalid U-Boot image: wrong architecture");
			}
			default: {
				throw Error("Invalid U-Boot image: error code " + image_type);
			}
		}
	}
	if(image_type !== IH_TYPE_FIRMWARE)
		throw Error("U-Boot image type mismatch: expected IH_TYPE_FIRMWARE, got " + image_type.toString(16) );

	let data_size = hdr.ih_size;
	let load_addr = hdr.ih_load;
	if(data_size > len - HEADER_SIZE)
		throw Error("U-Boot image data trucated: expected " + (len - HEADER_SIZE) +
					 "bytes, got " + data_size);

	let dcrc = hdr.ih_dcrc;
	let computed_dcrc = crc32(Array.from(new Uint8Array(buffer.slice(HEADER_SIZE, buffer.byteLength))));
	if (dcrc !== computed_dcrc)
	{
		throw Error("U-Boot data CRC mismatch: expected " + dcrc.toString(16) +
					", got " + computed_dcrc.toString(16));
	}

	debug("Writing image \"" + hdr.ih_name + "\", " + data_size.toString() +
						 " bytes @ 0x" + load_addr.toString(16) + ".");

	var data = buffer.slice(HEADER_SIZE, buffer.byteLength);
	await aw_write_buffer(data, load_addr, data_size);

	/* keep track of U-Boot memory region in global vars */
	uboot_entry = load_addr;
	uboot_size = data_size;

}

async function aw_enable_l2_cache()
{
	var arm_code = new ArrayBuffer(16);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xee112f30, true);	/* mrc        15, 0, r2, cr1, cr0, {1}  */
	view.setUint32(4, 0xe3822002, true);	/* orr        r2, r2, #2                */
	view.setUint32(8, 0xee012f30, true);	/* mcr        15, 0, r2, cr1, cr0, {1}  */
	view.setUint32(12, 0xe12fff1e, true);	/* bx         lr                        */

	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 16);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
}

async function aw_get_stackinfo()
{
	var arm_code = new ArrayBuffer(36);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe10f0000, true); 					/* mrs        r0, CPSR                  */
	view.setUint32(4, 0xe3c0101f, true);					/* bic        r1, r0, #31               */
	view.setUint32(8, 0xe3811012, true);					/* orr        r1, r1, #18               */
	view.setUint32(12, 0xe121f001, true);					/* msr        CPSR_c, r1                */
	view.setUint32(16, 0xe1a0100d, true);					/* mov        r1, sp                    */
	view.setUint32(20, 0xe121f000, true);					/* msr        CPSR_c, r0                */
	view.setUint32(24, 0xe58f1004, true);					/* str        r1, [pc, #4]              */
	view.setUint32(28, 0xe58fd004, true);					/* str        sp, [pc, #4]              */
	view.setUint32(32, 0xe12fff1e, true);					/* bx         lr                        */

	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 36);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
	let response = await aw_fel_read(dev_handle.soc_info.scratch_addr + 0x24, 8);
	var buffer = response.data.buffer;
	var view = new DataView(buffer);
	var result = new Uint32Array([view.getUint32(0, true), view.getUint32(4, true)]);
	return result;
}

async function aw_rmr_request(entry_point, aarch64)
{
	let soc_info = dev_handle.soc_info;
	if (!soc_info.rvbar_reg)
	{
		debug("ERROR: Can't issue RMR request!");
		debug("RVBAR is not supported or unknown for your SoC (" +soc_info.soc_name+").");
		return;
	}

	let rmr_mode = (1 << 1) | (aarch64 ? 1 : 0); /* RR, AA64 flag */
	var arm_code = new ArrayBuffer(60);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe59f0028, true); 					/* ldr        r0, [rvbar_reg]          */
	view.setUint32(4, 0xe59f1028, true);					/* ldr        r1, [entry_point]        */
	view.setUint32(8, 0xe5801000, true);					/* str        r1, [r0]                 */
	view.setUint32(12, 0xf57ff04f, true);					/* dsb        sy                       */
	view.setUint32(16, 0xf57ff06f, true);					/* isb        sy                       */
	view.setUint32(20, 0xe59f101c, true);					/* ldr        r1, [rmr_mode]           */
	view.setUint32(24, 0xee1c0f50, true);					/* mrc        15, 0, r0, cr12, cr0, {2}*/
	view.setUint32(28, 0xe1800001, true);					/* orr        r0, r0, r1               */
	view.setUint32(32, 0xee0c0f50, true);					/* mcr        15, 0, r0, cr12, cr0, {2}*/
	view.setUint32(36, 0xf57ff06f, true);					/* isb        sy                       */
	view.setUint32(40, 0xe320f003, true);					/* loop:      wfi                      */
	view.setUint32(44, 0xeafffffd, true);					/* b          <loop>                   */
	view.setUint32(48, soc_info.rvbar_reg, true);
	view.setUint32(52, entry_point, true);
	view.setUint32(56, rmr_mode, true);

	/* scratch buffer setup: transfers ARM code and parameter values */
	await aw_fel_write(arm_code, soc_info.scratch_addr, 60);
	/* execute the thunk code (triggering a warm reset on the SoC) */
	debug("Store entry point 0x" + entry_point.toString(16) +
				" to RVBAR 0x" + soc_info.rvbar_reg.toString(16) + ", and request warm reset with RMR mode " +
				 rmr_mode + "...");
	await aw_fel_execute(soc_info.scratch_addr);
	debug(" done.");
}

async function aw_backup_and_disable_mmu() {
	/* Disable I-cache, MMU and branch prediction */
	var arm_code = new ArrayBuffer(20);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xee110f10, true);	/* mrc        15, 0, r0, cr1, cr0, {0}  */
	view.setUint32(4, 0xe3c00001, true);	/* bic        r0, r0, #1                */
	view.setUint32(8, 0xe3c00b06, true);	/* bic        r0, r0, #0x1800           */
	view.setUint32(12, 0xee010f10, true);	/* mcr        15, 0, r0, cr1, cr0, {0}  */
	/* Return back to FEL */
	view.setUint32(16, 0xe12fff1e, true);	/* bx         lr                        */

	/*
	 * Below are some checks for the register values, which are known
	 * to be initialized in this particular way by the existing BROM
	 * implementations. We don't strictly need them to exactly match,
	 * but still have these safety guards in place in order to detect
	 * and review any potential configuration changes in future SoC
	 * variants (if one of these checks fails, then it is not a serious
	 * problem but more likely just an indication that one of these
	 * checks needs to be relaxed).
	 */

	// Check SCTLR
	try {
		let sctlr = await aw_get_sctlr();
		if ((sctlr & ~((0x7 << 11) | (1 << 6) | 1)) !== 0x00C50038)
		{
			throw Error("Unexpected SCTLR (" + sctlr.toString(16) + ")");
		}

		if (!(sctlr & 1)) {
			debug("MMU is not enabled by BROM");
			return null;
		}
	} catch (e) {
		throw e;
	}

	// Check DACR
	try {
		let dacr = await aw_get_dacr();
		if (dacr !== 0x55555555)
		{
			throw Error("Unexpected DACR (" + dacr.toString(16) + ")");
		}
	} catch (e) {
		throw e;
	}

	// Check TTBCR
	try {
		let ttbcr = await aw_get_ttbcr();
		if (ttbcr !== 0x00000000)
		{
			throw Error("Unexpected TTBCR (" + ttbcr.toString(16) + ")");
		}
	} catch (e) {
		throw e;
	}

	// Check TTBR0
	var ttbr0;
	try {
		ttbr0 = await aw_get_ttbr0();
		if (ttbr0 & 0x3FFF)
		{
			throw Error("Unexpected TTBR0 (" + ttbr0.toString(16) + ")");
		}
	} catch (e) {
		throw e;
	}

	//debug("Reading the MMU translation table from 0x" + ttbr0.toString(16));
	let response = await aw_fel_read(ttbr0, 16 * 1024);
	var buffer = response.data.buffer;
	var view = new DataView(buffer);
	var tt = new Uint32Array();
	var i = 0;
	var count = 4096;
	var length = 16 * 1024;
	while (count-- > 0 && length > i)
	{
		tt = concatenate(Uint32Array, tt, Uint32Array.of(view.getUint32(i, true)));
		i += 4;
	}
	/* Basic sanity checks to be sure that this is a valid table */
	for (i = 0; i < 4096; i++)
	{
		if (((tt[i] >> 1) & 1) !== 1 || ((tt[i] >> 18 & 1) !== 0))
		{
			throw Error("MMU: not a section descriptor");
		}
		if ((tt[i] >>> 20) !== i)
		{
			throw Error("MMU: not a direct mapping")
		}
	}
	
	//debug("Disabling I-cache, MMU and branch prediction...");
	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 20);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
	//debug("done");
	return tt;
}

async function aw_restore_and_enable_mmu(tt) {
	let ttbr0 = await aw_get_ttbr0();

	var arm_code = new ArrayBuffer(44);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe3a00000, true); 					/* mov        r0, #0                    */
	view.setUint32(4, 0xee080f17, true);					/* mcr        15, 0, r0, cr8, cr7, {0}  */
	view.setUint32(8, 0xee070f15, true);					/* mcr        15, 0, r0, cr7, cr5, {0}  */
	view.setUint32(12, 0xee070fd5, true);					/* mcr        15, 0, r0, cr7, cr5, {6}  */
	view.setUint32(16, 0xf57ff04f, true);					/* dsb        sy                        */
	view.setUint32(20, 0xf57ff06f, true);					/* isb        sy                        */
	/* Enable I-cache, MMU and branch prediction */
	view.setUint32(24, 0xee110f10, true);					/* mrc        15, 0, r0, cr1, cr0, {0}  */
	view.setUint32(28, 0xe3800001, true);					/* orr        r0, r0, #1                */
	view.setUint32(32, 0xe3800b06, true);					/* orr        r0, r0, #0x1800           */
	view.setUint32(36, 0xee010f10, true);					/* mcr        15, 0, r0, cr1, cr0, {0}  */
	/* Return back to FEL */
	view.setUint32(40, 0xe12fff1e, true);					/* bx         lr                        */

	//debug("Setting write-combine mapping for DRAM.");
	for (var i = (DRAM_BASE >> 20); i < ((DRAM_BASE + DRAM_SIZE) >> 20); i++) {
		/* Clear TEXCB bits */
		tt[i] &= ~((7 << 12) | (1 << 3) | (1 << 2));
		/* Set TEXCB to 00100 (Normal uncached mapping) */
		tt[i] |= (1 << 12);
	}

	//debug("Setting cached mapping for BROM.");
	/* Clear TEXCB bits first */
	tt[0xFFF] &= ~((7 << 12) | (1 << 3) | (1 << 2));
	/* Set TEXCB to 00111 (Normal write-back cached mapping) */
	tt[0xFFF] |= (1 << 12) | /* TEX */
				(1 << 3)  | /* C */
				(1 << 2);   /* B */

	//debug("Writing back the MMU translation table.\n");
	var buffer = tt.buffer;
	var view = new DataView(buffer);
	var tt_le = new Uint32Array();
	var count = 4096;
	i = 0;
	while (count-- > 0)
	{
		tt_le = concatenate(Uint32Array, tt_le, Uint32Array.of(view.getUint32(i, true)));
		i += 4;
	}
	await aw_fel_write(tt_le.buffer, ttbr0, 16 * 1024);

	debug("Enabling I-cache, MMU and branch prediction...");
	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 44);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
	debug("done");
}

async function aw_apply_smc_workaround() {
	let soc_info = dev_handle.soc_info;
	var arm_code = new ArrayBuffer(8);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xee110f10, true);	/* smc	#0	*/
	view.setUint32(4, 0xe3c00001, true);	/* bx	lr	*/

	if(soc_info.needs_smc_workaround_if_zero_word_at_addr === 0)
		return;

	var val = await aw_fel_read(soc_info.needs_smc_workaround_if_zero_word_at_addr, 4);

	if(val.data.getUint32() !== 0)
		return;

	debug("Applying SMC workaround... ");
	await aw_fel_write(soc_info.scratch_addr, 8);
	await aw_fel_execute(soc_info.scratch_addr);
	debug(" done.");
}

async function aw_get_sctlr()  {
	return await aw_read_arm_cp_reg(15, 0, 1, 0, 0);
}

async function aw_get_dacr() {
	return await aw_read_arm_cp_reg(15, 0, 3, 0, 0);
}

async function aw_get_ttbcr() {
	return await aw_read_arm_cp_reg(15, 0, 2, 0, 2);
}

async function aw_get_ttbr0() {
	return await aw_read_arm_cp_reg(15, 0, 2, 0, 0);
}

async function aw_set_sctlr(sctlr) {
	await aw_write_arm_cp_reg( 15, 0, 1, 0, 0, sctlr);
}

async function aw_set_dacr(dacr) {
	await aw_write_arm_cp_reg(15, 0, 3, 0, 0, dacr);
}

async function aw_set_ttbcr(ttbcr) {
	await aw_write_arm_cp_reg(15, 0, 2, 0, 2, ttbcr);
}

async function aw_set_ttbr0(ttbr0) {
	await aw_write_arm_cp_reg(15, 0, 2, 0, 0, ttbr0);
}

async function aw_read_arm_cp_reg(coproc, opc1, crn, crm, opc2) {
	var opcode = new DataView(new ArrayBuffer(4));
	opcode.setUint32(0, (0xEE000000 | (1 << 20) | (1 << 4)
	| ((opc1 & 0x7) << 21) | ((crn & 0xF) << 16)
	| ((coproc & 0xF) << 8) | ((opc2 & 0x7) << 5)
	| (crm & 0xF)));
	//debug("Read ARM CP Reg: " + opcode.getUint32(0).toString(16));

	var arm_code = new ArrayBuffer(12);
	var view = new DataView(arm_code);
	view.setUint32(0, opcode.getUint32(0), true);	/* mrc  coproc, opc1, r0, crn, crm, opc2 */
	view.setUint32(4, 0xe58f0000, true);			/* str  r0, [pc]                         */
	view.setUint32(8, 0xe12fff1e, true);			/* bx   lr                               */

	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 12);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
	let registerVal = await aw_fel_read(dev_handle.soc_info.scratch_addr + 12, 4);
	var buffer = registerVal.data.buffer;
	var view = new DataView(buffer);
	return view.getUint32(0, true);
}

async function aw_write_arm_cp_reg(coproc, opc1, crn, crm, opc2, val) {
	var opcode = new DataView(new ArrayBuffer(4));
	opcode.setUint32(0, (0xEE000000 | (0 << 20) | (1 << 4)
	| ((opc1 & 0x7) << 21) | ((crn & 0xF) << 16)
	| ((coproc & 0xF) << 8) | ((opc2 & 7) << 5)
	| (crm & 0xF)));
	//debug("Write ARM CP Reg: " + opcode.getUint32(0).toString(16));

	var arm_code = new ArrayBuffer(24);
	var view = new DataView(arm_code);
	view.setUint32(0, 0xe59f000c, true);			/* ldr  r0, [pc, #12]                    */
	view.setUint32(4, opcode.getUint32(0), true);	/* mcr  coproc, opc1, r0, crn, crm, opc2 */
	view.setUint32(8, 0xf57ff04f, true);			/* dsb  sy                               */
	view.setUint32(12, 0xf57ff06f, true);			/* isb  sy                               */
	view.setUint32(16, 0xe12fff1e, true);			/* bx   lr                               */
	view.setUint32(20, val, true);

	await aw_fel_write(arm_code, dev_handle.soc_info.scratch_addr, 24);
	await aw_fel_execute(dev_handle.soc_info.scratch_addr);
}

/*
 * Reconstruct the same MMU translation table as used by the A20 BROM.
 * We are basically reverting the changes, introduced in newer SoC
 * variants. This works fine for the SoC variants with the memory
 * layout similar to A20 (the SRAM is in the first megabyte of the
 * address space and the BROM is in the last megabyte of the address
 * space).
 */
async function aw_generate_mmu_translation_table() {
	var tt = new ArrayBuffer(4096 * 4);
	var view = new DataView(tt);
	var i,j = 0;

	for (i = 0; i < 4096 * 4; i+=4, j++)
	{
		view.setUint32(i, 0x00000DE2 | (j << 20));
	}
	;
	view.setUint32(0x000, (view.getUint32(0x000) | 0x1000));
	view.setUint32(0xFFF, (view.getUint32(0xFFF) | 0x1000));

	return tt;
}

/*
 * This wrapper for the FEL write functionality safeguards against overwriting
 * an already loaded U-Boot binary.
 * The return value represents elapsed time in seconds (needed for execution).
 */
async function aw_write_buffer(buffer, offset, len) {
	/* safeguard against overwriting an already loaded U-Boot binary */
	if (uboot_size > 0 && offset <= uboot_entry + uboot_size && offset + len >= uboot_entry)
		 throw Error("ERROR: Attempt to overwrite U-Boot! Request 0x" + offset.toString(16) + "-0x" +
					(offset+len).toString(16) + " overlaps  0x" + uboot_entry.toString(16) + "-0x" +
					uboot_size.toString(16) + ".");
	var d = new Date();
	var start = d.getTime();
	await aw_fel_write_buffer(buffer, offset, len);
	return (d.getTime() - start);
}

async function pass_fel_information(script_address, uEnv_length)
{
	/* write something _only_ if we have a suitable SPL header */
	var have_spl = await have_sunxi_spl(dev_handle.soc_info.spl_addr); 
	if(have_spl) {
		debug("Passing boot info via sunxi SPL: " +
		"script address = 0x" + script_address.toString(16) + 
		" uEnv length = " + uEnv_length.toString());

		var transfer = new ArrayBuffer(8);
		var view = new DataView(transfer);
		view.setUint32(0, script_address, true);               
		view.setUint32(4, uEnv_length, true);

		await aw_fel_write(transfer, dev_handle.soc_info.spl_addr + 0x18, 8);
	}
}

/*
 * Test the SPL header for our "sunxi" variant. We want to make sure that
 * we can safely use specific header fields to pass information to U-Boot.
 * In case of a missing signature (e.g. Allwinner boot0) or header version
 * mismatch, this function will return "false". If all seems fine,
 * the result is "true".
 */
async function have_sunxi_spl(spl_addr)
{
	let response = await aw_fel_read(spl_addr + 0x14, 4);
	var spl_view = response.data;
	var decoder = new TextDecoder('utf8');
	let spl_signature_string = decoder.decode(response.data).replace(/[^\x20-\x7E]/g, '');


	if(SPL_SIGNATURE !== spl_signature_string)
		return false; /* signature mismatch, no "sunxi" SPL */

	if(spl_view.getUint8(3) < SPL_MIN_VERSION) {
		debug("Sunxi SPL version mismatch: " + 
		"found 0x" + spl_view.getUint8(3).toString(16) + " < required minimum 0x" + 
		SPL_MIN_VERSION.toString(16));
		debug("You need to update your U-Boot (mksunxiboot) to a more recent version.");
		return false;
	}

	if(spl_view.getUint8(3) > SPL_MAX_VERSION) {
		debug("Sunxi SPL version mismatch: " + 
		"found 0x" + spl_view.getUint8(3).toString(16) + " < required maximum 0x" + 
		SPL_MAX_VERSION.toString(16));
		debug("You need a more recent version of this (sunxi-tools) fel utility.");
		return false;
	}

	return true; /* sunxi SPL and suitable version */
}

async function file_upload()
{
	var i;
	/* load file into memory buffer */
	for (i in uploadedFiles)
	{
		if(uploadedFiles[i].name.includes("u-boot-sunxi-with-spl.bin")) { continue; }
		var offset = uploadedFiles[i].offset;
		var size = uploadedFiles[i].data.byteLength;
		debug("Writing: " + uploadedFiles[i].name);
		await aw_write_buffer(uploadedFiles[i].data, offset, size);

		/* If we transferred a script, try to inform U-Boot about its address. */
		var header = new image_header(uploadedFiles[i].data.slice(0, HEADER_SIZE));

		if( header.image_type(size) === IH_TYPE_SCRIPT )
			await pass_fel_information(offset, 0);
	}
	return Promise.resolve("Wrote all files");
}

async function aw_start_uboot() {
	debug("Starting U-Boot (0x" + uboot_entry.toString(16) + ").");
	await aw_fel_execute(uboot_entry);
}

async function feldev_open() {
	return dev_handle.device.open()
		.then(()=> dev_handle.device.selectConfiguration(1))
		.then(() => dev_handle.device.claimInterface(dev_handle.device.configuration.interfaces[0].interfaceNumber))
		/* retrieve BROM version and SoC information */
		.then(() => aw_fel_get_version())
		.then(() => {
			let id = dev_handle.soc_version.soc_id;
			dev_handle.soc_name = get_soc_name_from_id(id);
			dev_handle.soc_info = get_soc_info_from_id(id);
		})
		.then(() => aw_apply_smc_workaround());
}

/* ------------------------------------	*/
/* Our Commands 						*/
/* ------------------------------------	*/
export async function flash() {
	var nandInfo;
	var NAND_OOB_SIZE_HEX;
	var RAW_NAND_TYPE;

	try {
		let result = await cdb({
							method: 'get',
							url: 'info',
							baseURL: cdbURL,
							responseType: 'json',
					});
		debug(JSON.stringify(result.data));
		nandInfo = result.data;

		NAND_OOB_SIZE_HEX=nandInfo[0].OobSize.toString(16);
		if (NAND_OOB_SIZE_HEX === '680')
			RAW_NAND_TYPE="RAW_NAND_HYNIX";
		else
			RAW_NAND_TYPE="RAW_NAND_TOSHIBA";
	}
	catch (error) {
		debug(error.message);
		return;
	}

	var dest, file, type;

	if (type === "RAW_NAND_HYNIX" || type === "RAW_NAND_TOSHIBA")
	{

	}
	else if (type === "NAND")
	{

	}
	else if (type === "UBIFS_TAR")
	{
		try {
			await create_ubi(nandInfo);
		}
		catch (error) {
			debug(error.message);
			return;
		}

		debug("Attach UBI volume...");
		try {
			let result = await cdb({
								method: 'post',
								url: 'run',
								baseURL: cdbURL,
								data: 'cmd=/usr/sbin/ubiattach -m4',
								responseType: 'arraybuffer',
								onDownloadProgress: function (progressEvent) {
									var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
									  document.getElementById('progress').innerHTML = percentCompleted;
								},
						});
			debug(result.statusText);
		}
		catch (error) {
			debug(error.message);
			return;
		}

		debug("Create mount point...");
		try {
			let result = await cdb({
								method: 'post',
								url: 'run',
								baseURL: cdbURL,
								data: 'cmd=/bin/mkdir -p /rootfs',
						});
			debug(result.statusText);
		}
		catch (error) {
			debug(error.message);
			return;
		}

		debug("Mount UBIFS...");
		try {
			let result = await cdb({
								method: 'post',
								url: 'run',
								baseURL: cdbURL,
								data: 'cmd=/bin/mount -t ubifs /dev/ubi0_0 /rootfs',
						});
			debug(result.statusText);
		}
		catch (error) {
			debug(error.message);
			return;
		}

		debug("Untar rootfs...");
		var rootfs;
		try {
			let result = await cdb({
				method: 'get',
				url: 'restore',
				baseURL: cdbURL,
				data: rootfs,
				onUploadProgress: function (progressEvent) {
					var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
					  document.getElementById('progress').innerHTML = percentCompleted;
				},
			});
			debug(result.statusText);
		}
		catch {
			document.getElementById('state').innerHTML = "Network Error";
		}
		document.getElementById('progress').innerHTML = "";

		debug("Unmount UBIFS...");
		try {
			let result = await cdb({
								method: 'post',
								url: 'run',
								baseURL: cdbURL,
								data: 'cmd=/bin/umount /rootfs',
						});
			debug(result.statusText);
		}
		catch (error) {
			debug(error.message);
			return;
		}

		debug("Deattach UBI volume...");
		try {
			let result = await cdb({
								method: 'post',
								url: 'run',
								baseURL: cdbURL,
								data: 'cmd=/usr/sbin/ubidetach -m4',
						});
			debug(result.statusText);
		}
		catch (error) {
			debug(error.message);
			return;
		}


	}

}

// TODO: Get NAND info from info.json
async function create_ubi(infoJSON) {

	var NAND_SIZE, NAND_BLOCKS, NAND_ERASE_SIZE, NAND_ERASE_SIZE_HEX,
	NAND_SUBPAGE_SIZE_HEX, NAND_WRITE_SIZE_HEX;

	NAND_ERASE_SIZE=infoJSON[0].EraseSize;
	NAND_ERASE_SIZE_HEX=infoJSON[0].EraseSize.toString(16);
	NAND_SUBPAGE_SIZE_HEX=infoJSON[0].SubPageSize.toString(16);
	NAND_WRITE_SIZE_HEX=infoJSON[0].WriteSize.toString(16);

	for (var dest in infoJSON)
	{
		if(infoJSON[dest].Path === "/dev/mtd4"){
			NAND_SIZE = infoJSON[dest].Size;
			NAND_BLOCKS = NAND_SIZE / NAND_ERASE_SIZE;
		}
	}

	debug("Uploading ubi.cfg...");
	let ubiConfig = createUBIConfig(NAND_SIZE);
	try {
		let result = await cdb({
						method: 'post',
						url: 'file/tmp/ubi.cfg',
						baseURL: cdbURL,
						data: ubiConfig,
					});
		debug(result.statusText);
	}
	catch(error) {
		debug(error.message);
		return;
	}

	debug("Run ubinize...");
	try {
		let cmd = 	'cmd=/usr/sbin/ubinize -o /tmp/ubi.bin -p 0x' + NAND_ERASE_SIZE_HEX +
					' -m 0x' + NAND_WRITE_SIZE_HEX + '-s 0x' + NAND_SUBPAGE_SIZE_HEX +
					' -M dist3 /tmp/ubi.cfg';
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: cmd,
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Run flash_erase...");
	try {
		let cmd = 'cmd=/usr/sbin/flash_erase /dev/mtd4 0 ' + NAND_BLOCKS;
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: cmd,
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Run nand_write...");
	try {
		let cmd = 'cmd=/usr/sbin/nandwrite -m -p /dev/mtd4 /tmp/ubi.bin';
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: cmd,
							responseType: 'arraybuffer',
							onDownloadProgress: function (progressEvent) {
								var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
								  document.getElementById('progress').innerHTML = percentCompleted;
							},
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}
}

function createUBIConfig(NAND_SIZE) {
	let NAND_SEC_PERCENT = 12;
	let VOL_SIZE=NAND_SIZE - ((NAND_SIZE * NAND_SEC_PERCENT) / 100);

	var bb = [];

	bb.push("[rootfs]\n");
	bb.push("mode=ubi\n");
	bb.push("vol_id=0\n");
	bb.push("vol_size="+VOL_SIZE+"\n");
	bb.push("vol_type=dynamic\n");
	bb.push("vol_name=rootfs\n");
	bb.push("vol_alignment=1\n");

	let ubiConfig = new Blob(bb, {type: "text/plain"});
	let ubiConfigFile = new File([ubiConfig], "ubiConfig");
	return ubiConfigFile;
}

export async function clone() {

	//var files = [];

	var zip = new JSZip();

	var nandInfo;
	var NAND_OOB_SIZE;
	var RAW_NAND_TYPE;
	try {
		let result = await cdb({
							method: 'get',
							url: 'info',
							baseURL: cdbURL,
							responseType: 'json',
					});
		debug(JSON.stringify(result.data));
		nandInfo = result.data;
		//var f = new File([JSON.stringify(result.data)], 'info.json');
		//files.push(f);

		zip.file('info.json', JSON.stringify(result.data), { binary: true});

		NAND_OOB_SIZE=nandInfo[0].OobSize; 
		if (NAND_OOB_SIZE === '1664')
			RAW_NAND_TYPE="RAW_NAND_HYNIX";
		else
			RAW_NAND_TYPE="RAW_NAND_TOSHIBA";
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("-- Download SPL --");
	debug("Read SPL from /dev/mtd0");
	//var SPLmtd0;
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/nanddump -a -o -n /dev/mtd0',
							responseType: 'arraybuffer',
							onDownloadProgress: function (progressEvent) {
								var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
								  document.getElementById('progress').innerHTML = percentCompleted;
							},
					});
		//SPLmtd0 = result.data;
		//var f = new File([SPLmtd0], 'mtd0');
		//files.push(f);

		zip.file('mtd0', result.data, { binary: true});
	}
	catch (error) {
		debug(error.message);
		return;
	}
	document.getElementById('progress').innerHTML = "";

	debug("Read SPL from /dev/mtd1");
	//var SPLmtd1;
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/nanddump -a -o -n /dev/mtd1',
							responseType: 'arraybuffer',
							onDownloadProgress: function (progressEvent) {
								var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
								  document.getElementById('progress').innerHTML = percentCompleted;
							},
					});
		//SPLmtd1 = result.data;
		//var f = new File([SPLmtd1], 'mtd1');
		//files.push(f);

		zip.file('mtd1', result.data, { binary: true});
	}
	catch (error) {
		debug(error.message);
		return;
	}
	document.getElementById('progress').innerHTML = "";

	debug("-- Download U-Boot --");
	debug("Read U-Boot from /dev/mtd2");
	//var UBOOTmtd2;
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/nanddump -a -o -n /dev/mtd2',
							responseType: 'arraybuffer',
							onDownloadProgress: function (progressEvent) {
								var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
								  document.getElementById('progress').innerHTML = percentCompleted;
							},
					});
		//UBOOTmtd2 = result.data;
		//var f = new File([UBOOTmtd2], 'mtd2');
		//files.push(f);

		zip.file('mtd2', result.data, { binary: true});
	}
	catch (error) {
		debug(error.message);
		return;
	}
	document.getElementById('progress').innerHTML = "";

	debug("-- Download U-Boot Environment --");
	debug("Read U-Boot Environment from /dev/mtd3");
	//var ubootENVmtd3;
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/nanddump -a -o -n /dev/mtd3',
							responseType: 'arraybuffer',
							onDownloadProgress: function (progressEvent) {
								var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
								  document.getElementById('progress').innerHTML = percentCompleted;
							},
					});
		//ubootENVmtd3 = result.data;
		//var f = new File([ubootENVmtd3], 'mtd3');
		//files.push(f);

		zip.file('mtd3', result.data, { binary: true});
	}
	catch (error) {
		debug(error.message);
		return;
	}
	document.getElementById('progress').innerHTML = "";

	await sleep(1000);

	debug("Attach UBI volume...");
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/ubiattach -m4',
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Create mount point...");
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/bin/mkdir -p /rootfs',
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Mount UBIFS...");
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/bin/mount -t ubifs /dev/ubi0_0 /rootfs',
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Downloading rootfs...");
	//var rootfs;
	try {
		let result = await cdb({
			method: 'get',
			url: 'backup',
			baseURL: cdbURL,
			responseType: 'arraybuffer',
			onDownloadProgress: function (progressEvent) {
				var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
				  document.getElementById('progress').innerHTML = percentCompleted;
			},
		});
		//rootfs = result.data;
		//var f = new File([rootfs], 'rootfs.tar');
		//files.push(f);

		zip.file('rootfs.tar', result.data, { binary: true});
	}
	catch {
		document.getElementById('state').innerHTML = "Network Error";
	}
	document.getElementById('progress').innerHTML = "";

	debug("Unmount UBIFS...");
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/bin/umount /rootfs',
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	debug("Deattach UBI volume...");
	try {
		let result = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/sbin/ubidetach -m4',
					});
		debug(result.statusText);
	}
	catch (error) {
		debug(error.message);
		return;
	}

	// Create manifest.ini file
	//files.push(createManifestINI(RAW_NAND_TYPE));
	let manifestini = createManifestINI(RAW_NAND_TYPE);
	zip.file(manifestini.name, await readUploadedFile(manifestini), { binary: true});

	// Create manifest.json file
	//files.push(createManifestJSON(RAW_NAND_TYPE));
	let manifestjson = createManifestJSON(RAW_NAND_TYPE);
	zip.file(manifestjson.name, await readUploadedFile(manifestjson), { binary: true});

	//var file;
	//for(file in files) {
	//
	//}

	zip.generateAsync({type:"blob"})
	.then(function (blob) {
		saveAs(blob, "clone.zip");
	});

}

function createManifestINI(RAW_NAND_TYPE) {
	var bb = [];
	bb.push("[info]\ndescription=fel.js\nfry_version=0\n");
	bb.push("[mtd0]\ndestination=/dev/mtd0\nfile=mtd0\ntype="+RAW_NAND_TYPE+"\n");
	bb.push("[mtd0]\ndestination=/dev/mtd1\nfile=mtd1\ntype="+RAW_NAND_TYPE+"\n");
	bb.push("[mtd2]\ndestination=/dev/mtd2\nfile=mtd2\ntype=NAND\n");
	bb.push("[mtd3]\ndestination=/dev/mtd3\nfile=mtd3\ntype=NAND\n");
	bb.push("[rootfs]\ndestination=/dev/ubi0_0\nfile=rootfs.tar\ntype=UBIFS_TAR\n");

	let manifest = new Blob(bb, {type: "text/plain"});
	let manifestFile = new File([manifest], "manifest.ini");
	return manifestFile;
}

function createManifestJSON(RAW_NAND_TYPE) {
	var bb = [];
	bb.push("[\n")
	bb.push("{\n\"destination\": \"/dev/mtd0\",\n\"file\": \"mtd0\",\n\"type\": \""+RAW_NAND_TYPE+"\"\n},\n");
	bb.push("{\n\"destination\": \"/dev/mtd1\",\n\"file\": \"mtd1\",\n\"type\": \""+RAW_NAND_TYPE+"\"\n},\n");
	bb.push("{\n\"destination\": \"/dev/mtd2\",\n\"file\": \"mtd2\",\n\"type\": \"NAND\"\n},\n");
	bb.push("{\n\"destination\": \"/dev/mtd3\",\n\"file\": \"mtd3\",\n\"type\": \"NAND\"\n},\n");
	bb.push("{\n\"destination\": \"/dev/ubi0_0\",\n\"file\": \"rootfs.tar\",\n\"type\": \"UBIFS_TAR\"\n}\n");

	let manifest = new Blob(bb, {type: "text/plain"});
	let manifestFile = new File([manifest], "manifest.json");
	return manifestFile;
}


async function detectNANDType() {
	var nandInfo;
	try {
		nandInfo = await await cdb({
									method: 'get',
									url: 'info',
									baseURL: cdbURL
								});
		debug(JSON.stringify(nandInfo.data));
	}
	catch (error) {
		debug(error.message);
	}
}

async function partition() {
	const response = await cdb({
						method: 'post',
						url: 'run',
						baseURL: cdbURL,
						data: 'cmd=/usr/bin/partition.sh',
					});
	if(response)
		debug("Create boot partition: " + response.statusText);
}

async function format() {
	const response = await cdb({
						method: 'post',
						url: 'run',
						baseURL: cdbURL,
						data: 'cmd=/usr/bin/format.sh',
					});
	if(response)
		debug("Format partitions: " + response.statusText);
}

async function mount() {
	const response = await cdb({
							method: 'post',
							url: 'run',
							baseURL: cdbURL,
							data: 'cmd=/usr/bin/mount.sh',
						});
	if(response)
		debug("Mount partitions: " + response.statusText);
}

export async function formatAndMount() {
	cdb({
		method: 'post',
		url: 'run',
		baseURL: cdbURL,
		data: 'cmd=/bin/mkdir -p /mnt/boot /mnt/card',
		})
		.then(response => {
			if(response)
				debug("Make /mnt boot and card directories: " + response.statusText);
		  })
		.then(() => partition())
		.then(() => format())
		.then(() => mount())
		.catch(error => {
				console.error(error.message);
		});
}

export async function getAssets(name = null) {
	if (!name && dev_handle && dev_handle.soc_name === "A64") {
		name = 'PocketPC';
	} else if (!name) {
		name = 'Popcorn';
	}
	var output = [];
	uploadedFiles = [];

	document.getElementById('state').innerHTML = "Not Loaded";
	
	// TODO: decide the array of assets to use based on the `name` parameter.
	// It can be one of: CHIP, CHIPPro, Popcorn, Kettlepop, bananapi, orangepi.
	// See test.parts, App.js line 79.
	
	let popcornAssets = ["boot.scr.bin", "sun5i-gr8-kettlepop.dtb", "u-boot-sunxi-with-spl.bin", "rootfs.cpio.uboot", "zImage"];
	let chipAssets = ["boot.scr.bin", "sun5i-r8-chip.dtb", "u-boot-sunxi-with-spl.bin", "rootfs.cpio.uboot", "zImage"]
	let a64Assets = ["boot.scr.bin", "sun50i-a64-pocketpc.dtb", "u-boot-sunxi-with-spl.bin", "initramfs.gz", "Image.gz"];

	var assets;
	if (name === "Popcorn" || name === "Kettlepop") {
		assets = popcornAssets;
	}
	else if(name === "CHIP" || name === "CHIPPro") {
		assets = chipAssets;
	}
	else if(name === "PocketPC") {
		assets = a64Assets;
	}

	var file;

	let baseURL;
	if (name === "PocketPC") {
		baseURL = '/assets/PocketPC/';
	} else {
		baseURL = `https://storage.source.parts/parts/fel/${name}/`;
	}

	for(file in assets) {
		var response;
		try {
			response = await cdb({
				method: 'get',
				url: assets[file],
				baseURL: baseURL,
				responseType: 'arraybuffer',
				onDownloadProgress: function (progressEvent) {
					var percentCompleted = Math.round( (progressEvent.loaded * 100) / progressEvent.total );
					  document.getElementById('progress').innerHTML = percentCompleted;
				},
			});
		}
		catch {
			document.getElementById('state').innerHTML = "Network Error";
			break;
		}

		let view = new DataView(response.data);
		var d = Date.parse(response.headers["last-modified"]);
		var f = new File([view], assets[file], {
			type: response.headers["content-type"],
			lastModified: d,
		})
		output.push('<li><strong>', escape(f.name), '</strong> (', f.type || 'n/a', ') - ',
					f.size, ' bytes, last modified: ',
					f.lastModifiedDate ? f.lastModifiedDate.toLocaleDateString() : 'n/a',
					'</li>')
		uploadedFiles.push( { "name": f.name, "offset": 0x43100000, "data": response.data } );
		document.getElementById('list').innerHTML = '<ul>' + output.join('') + '</ul>';
	}
	document.getElementById('progress').innerHTML = "";
	document.getElementById('state').innerHTML = "Loaded";
}

export function startBoot () {
	if(dev_handle !== undefined)
	{
		feldev_open()
		.then(() => aw_fel_process_spl_and_uboot())
		.then(() => file_upload())
		.then(() => {
			if (dev_handle.soc_name === "A13"){
				var uboot_autostart = (uboot_entry > 0 && uboot_size > 0);
				if(!uboot_autostart)
				debug("Warning: \"uboot\" command failed to detect image! Can't execute U-Boot.");
				else {
					aw_start_uboot();
				}
			}
			else if (dev_handle.soc_name === "A64") {
				aw_rmr_request(0x44000, true);
			}

		})
		.catch(error => {
			debug(dev_handle.device);
			debug(error.message);
		});
	}
	else{
		debug("Device not connected");
		return;
	}
}

export function getSerialID () {
	if(dev_handle !== undefined)
	{
		feldev_open()
		.then(() => aw_fel_print_sid())
		.catch(error => { 
			debug(dev_handle.device);
			debug(error.message); 
		});
	}
	else{
		debug("Device not connected");
		return;
	}
}

export function getNANDType () {
		detectNANDType()
		.catch(error => {
			debug(error.message);
		});
}

export function getVersion () {
	if(dev_handle !== undefined)
	{
		feldev_open()
		.then(()=> aw_fel_get_version())
		.then(result => {
			aw_fel_print_version(result);
			debug(result);

		})
		.catch(error => { 
			debug(dev_handle.device);
			debug(error.message);
		});
	}
	else{
		debug("Device is not connected");
		return;
	}

}

export async function getDevice() {
	return navigator.usb.requestDevice({ filters: [{ vendorId: AW_USB_VENDOR_ID }] })
	.then(selectedDevice => {
	  dev_handle = new feldev_handle(selectedDevice);
	  debug("Device connected");
	})
	.then(() => { getVersion(); })
	.catch(error => {
		debug(error.message);
		throw error;
	});
}

navigator.usb.addEventListener('connect', event => {
	debug("Device connected");
	let el = document.getElementById("state");
	if (el) el.innerText = "Connected";
	let dot = document.getElementById("statusDot");
	if (dot) dot.classList.add("connected");
});

navigator.usb.addEventListener('disconnect', event => {
	debug("Device disconnected");
	let el = document.getElementById("state");
	if (el) el.innerText = "Disconnected";
	let dot = document.getElementById("statusDot");
	if (dot) dot.classList.remove("connected");

	let sid = document.getElementById("serialIDResult");
	if (sid) sid.innerHTML = "";
	let ver = document.getElementById("versionResult");
	if (ver) ver.innerHTML = "";
	uboot_entry = 0;
	uboot_size = 0;
});

export async function readMemory() {
	if (!dev_handle) { debug("Device not connected"); return; }
	let addr = prompt("Memory address (hex):", "0x40000000");
	if (!addr) return;
	let len = prompt("Length (bytes):", "256");
	if (!len) return;
	addr = parseInt(addr, 16);
	len = parseInt(len);
	try {
		await feldev_open();
		let data = await aw_fel_read(addr, len);
		let hex = '';
		let u8 = new Uint8Array(data);
		for (let i = 0; i < u8.length; i += 16) {
			let line = (addr + i).toString(16).padStart(8, '0') + ': ';
			for (let j = 0; j < 16 && (i + j) < u8.length; j++) {
				line += u8[i + j].toString(16).padStart(2, '0') + ' ';
			}
			hex += line + '\n';
		}
		document.getElementById("consoleOutput").innerText = hex;
		debug("Read " + len + " bytes from 0x" + addr.toString(16));
	} catch (e) { debug(e.message); }
}

export async function writeMemory() {
	if (!dev_handle) { debug("Device not connected"); return; }
	let addr = prompt("Write address (hex):", "0x40000000");
	if (!addr) return;
	let hexData = prompt("Hex data (e.g. DEADBEEF):");
	if (!hexData) return;
	addr = parseInt(addr, 16);
	let bytes = new Uint8Array(hexData.match(/.{1,2}/g).map(b => parseInt(b, 16)));
	try {
		await feldev_open();
		await aw_fel_write(bytes.buffer, addr, bytes.length);
		debug("Wrote " + bytes.length + " bytes to 0x" + addr.toString(16));
	} catch (e) { debug(e.message); }
}

export async function executeAddr() {
	if (!dev_handle) { debug("Device not connected"); return; }
	let addr = prompt("Execute address (hex):", "0x40000000");
	if (!addr) return;
	addr = parseInt(addr, 16);
	try {
		await feldev_open();
		await aw_fel_execute(addr);
		debug("Executed at 0x" + addr.toString(16));
	} catch (e) { debug(e.message); }
}

export async function readSPINOR() {
	if (!dev_handle) { debug("Device not connected"); return; }
	let addr = prompt("SPI NOR offset:", "0x0");
	let len = prompt("Length:", "4096");
	if (!addr || !len) return;
	addr = parseInt(addr, 16);
	len = parseInt(len);
	debug("Reading SPI NOR at 0x" + addr.toString(16) + " (" + len + " bytes)...");
	debug("SPI NOR read requires DRAM init and SPI0 setup — not yet implemented in fel.js");
	debug("Use sunxi-fel CLI: sunxi-fel spiflash-read " + addr + " " + len + " output.bin");
}

export async function probeUARTs() {
	if (!dev_handle) { debug("Device not connected"); return; }
	try {
		await feldev_open();
		let output = "=== UART Probe ===\n";
		output += "(non-destructive: all registers restored after probe)\n\n";

		// Save all registers we'll modify
		let saved = {};
		const save_addrs = [
			0x01C20068, 0x01C2006C, 0x01C202D8,  // clocks + resets
			0x01C20824, 0x01C20864, 0x01C20898,    // PB, PD, PG pin mux
		];
		for (let addr of save_addrs) {
			saved[addr] = await fel_readl(addr);
		}
		output += "Saved " + save_addrs.length + " registers\n\n";

		// Enable PIO clock
		await fel_writel(0x01C20068, saved[0x01C20068] | 0x00000020);

		// Enable all UART clocks (UART0-4) + deassert resets
		await fel_writel(0x01C2006C, saved[0x01C2006C] | 0x001F0000);
		await fel_writel(0x01C202D8, saved[0x01C202D8] | 0x001F0000);

		const uarts = [
			{ name: "UART0", base: 0x01C28000, pins: "PF2/PF4 (secure domain)" },
			{ name: "UART1", base: 0x01C28400, pins: "PG6/PG7" },
			{ name: "UART2", base: 0x01C28800, pins: "PB0/PB1" },
			{ name: "UART3", base: 0x01C28C00, pins: "PD0/PD1" },
			{ name: "UART4", base: 0x01C29000, pins: "PD2/PD3" },
		];

		// Configure pin muxes
		// PB0=UART2-TX(f2), PB1=UART2-RX(f2)
		await fel_writel(0x01C20824, 0x77777722);
		// PD0=UART3-TX(f3), PD1=UART3-RX(f3)
		let pd_cfg = await fel_readl(0x01C20864);
		await fel_writel(0x01C20864, (pd_cfg & 0xFFFFFF00) | 0x33);
		// PD2=UART4-TX(f3), PD3=UART4-RX(f3)
		await fel_writel(0x01C20864, (pd_cfg & 0xFFFF0000) | 0x3333);
		// PG6=UART1-TX(f2), PG7=UART1-RX(f2)
		await fel_writel(0x01C20898, 0x22000000);

		for (let uart of uarts) {
			// Configure 115200 8N1
			await fel_writel(uart.base + 0x0C, 0x83); // LCR DLAB=1
			await fel_writel(uart.base + 0x00, 0x0D); // DLL (115200 @ 24MHz)
			await fel_writel(uart.base + 0x04, 0x00); // DLH
			await fel_writel(uart.base + 0x0C, 0x03); // LCR 8N1
			await fel_writel(uart.base + 0x08, 0x07); // FCR enable+reset

			// Send identifier
			let msg = uart.name + "\r\n";
			for (let c of msg) {
				await fel_writel(uart.base + 0x00, c.charCodeAt(0));
			}

			// Read LSR to check TX status
			let lsr = await fel_readl(uart.base + 0x14);
			output += uart.name + " (" + uart.pins + "): LSR=0x" + lsr.toString(16) + "\n";
		}

		output += "\nSent identifier on each UART.\n";
		output += "Check your serial terminal for which one shows output.\n\n";

		// Restore all saved registers
		output += "Restoring registers...\n";
		for (let addr of save_addrs) {
			await fel_writel(addr, saved[addr]);
		}
		output += "All registers restored to original state.\n";

		document.getElementById("consoleOutput").innerText = output;
		debug("UART probe complete (state preserved)");
	} catch (e) { debug(e.message); }
}

export async function readRegisters() {
	if (!dev_handle) { debug("Device not connected"); return; }
	try {
		await feldev_open();
		let output = "=== A64 Key Registers ===\n\n";

		// CCU registers
		output += "--- Clock Control ---\n";
		let val = await fel_readl(0x01C20068);
		output += "BUS_CLK_GATE2 (PIO):   0x" + val.toString(16).padStart(8, '0') + "\n";
		val = await fel_readl(0x01C2006C);
		output += "BUS_CLK_GATE3 (UART):  0x" + val.toString(16).padStart(8, '0') + "\n";

		// GPIO config
		output += "\n--- GPIO Port Config ---\n";
		const ports = [
			{ name: "PB_CFG0", addr: 0x01C20824 },
			{ name: "PB_CFG1", addr: 0x01C20828 },
			{ name: "PD_CFG0", addr: 0x01C20864 },
			{ name: "PF_CFG0", addr: 0x01C20854 },
			{ name: "PG_CFG0", addr: 0x01C20898 },
			{ name: "PH_CFG0", addr: 0x01C20874 },
			{ name: "PH_CFG1", addr: 0x01C20878 },
		];
		for (let p of ports) {
			val = await fel_readl(p.addr);
			output += p.name + ": 0x" + val.toString(16).padStart(8, '0') + "\n";
		}

		// GPIO data
		output += "\n--- GPIO Port Data ---\n";
		const data_ports = [
			{ name: "PB_DAT", addr: 0x01C20834 },
			{ name: "PD_DAT", addr: 0x01C2086C },
			{ name: "PF_DAT", addr: 0x01C20858 },
			{ name: "PG_DAT", addr: 0x01C208A8 },
			{ name: "PH_DAT", addr: 0x01C2087C },
		];
		for (let p of data_ports) {
			val = await fel_readl(p.addr);
			output += p.name + ": 0x" + val.toString(16).padStart(8, '0') + "\n";
		}

		// R_PIO (secure domain)
		output += "\n--- Secure GPIO (R_PIO) ---\n";
		val = await fel_readl(0x01F02C00);
		output += "PL_CFG0: 0x" + val.toString(16).padStart(8, '0') + "\n";
		val = await fel_readl(0x01F02C10);
		output += "PL_DAT:  0x" + val.toString(16).padStart(8, '0') + "\n";

		document.getElementById("consoleOutput").innerText = output;
		debug("Register dump complete");
	} catch (e) { debug(e.message); }
}

export async function readEMMCHeaders() {
	if (!dev_handle) { debug("Device not connected"); return; }
	debug("Reading eMMC headers...");
	debug("eMMC access via FEL requires loading SPL first to init DRAM + MMC controller");
	try {
		await feldev_open();
		// Read the first 512 bytes at DRAM base after boot to check for MBR/GPT
		let data = await aw_fel_read(0x0, 512);
		let u8 = new Uint8Array(data);
		let hex = '';
		for (let i = 0; i < u8.length; i += 16) {
			let line = i.toString(16).padStart(8, '0') + ': ';
			for (let j = 0; j < 16 && (i + j) < u8.length; j++) {
				line += u8[i + j].toString(16).padStart(2, '0') + ' ';
			}
			hex += line + '\n';
		}
		document.getElementById("consoleOutput").innerText = hex;
		debug("Read 512 bytes from SRAM 0x0 — check for boot headers");
	} catch (e) { debug(e.message); }
}

export async function getSoCInfo() {
	if (!dev_handle) { debug("Device not connected"); return; }
	try {
		await feldev_open();
		let info = dev_handle.soc_info;
		let output = "";
		output += "SoC:             " + info.soc_name + "\n";
		output += "SoC ID:          0x" + info.soc_id.toString(16) + "\n";
		output += "SPL Address:     0x" + info.spl_addr.toString(16) + "\n";
		output += "Scratch Address: 0x" + info.scratch_addr.toString(16) + "\n";
		output += "Thunk Address:   0x" + info.thunk_addr.toString(16) + "\n";
		output += "Thunk Size:      " + info.thunk_size + "\n";
		output += "MMU TT Address:  0x" + info.mmu_tt_addr.toString(16) + "\n";
		output += "SID Base:        0x" + info.sid_base.toString(16) + "\n";
		output += "SID Offset:      0x" + info.sid_offset.toString(16) + "\n";
		output += "RVBAR Register:  0x" + (info.rvbar_register || 0).toString(16) + "\n";
		output += "Swap Buffers:    " + info.swap_buffers.length + " entries\n";
		for (let i = 0; i < info.swap_buffers.length; i++) {
			let sb = info.swap_buffers[i];
			output += "  [" + i + "] BROM: 0x" + sb.buf1.toString(16) +
				" Backup: 0x" + sb.buf2.toString(16) +
				" Size: 0x" + sb.size.toString(16) + "\n";
		}
		document.getElementById("consoleOutput").innerText = output;
		debug("SoC info retrieved");
	} catch (e) { debug(e.message); }
}

export async function handleFileSelect(evt) {
    var files = evt.target.files; // FileList object

    // files is a FileList of File objects. List some properties.
    var output = [];
    for (var i = 0, f; f = files[i]; i++) {
		output.push('<li><strong>', escape(f.name), '</strong> (', f.type || 'n/a', ') - ',
                  f.size, ' bytes, last modified: ',
                  f.lastModifiedDate ? f.lastModifiedDate.toLocaleDateString() : 'n/a',
				  '</li>');
		if (f.name === "u-boot-sunxi-with-spl.bin" || f.name === "sunxi-a64-spl32-ddr3.bin")
		{
			try {
				var uboot = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "data": uboot } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name === "u-boot.bin")
		{
			try {
				var uboot = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x4a000000, "data": uboot } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name === "bl31-a64-h5.bin")
		{
			try {
				var bl31 = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x44000, "data": bl31 } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name.includes(".dtb"))
		{
			try {
				var deviceTree = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x43000000, "data": deviceTree } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name === "zImage")
		{
			try {
				var zImage = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x42000000, "data": zImage } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name.includes("rootfs"))
		{
			try {
				var rootfs = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x43300000, "data": rootfs } );
			} catch (e) {
				debug(e.message);
			}
		}
		else if (f.name.includes(".scr.bin"))
		{
			try {
				var bootScript = await readUploadedFile(f);
				uploadedFiles.push( { "name": f.name, "offset": 0x43100000, "data": bootScript } );
			} catch (e) {
				debug(e.message);
			}
		}
    }
	document.getElementById('list').innerHTML = '<ul>' + output.join('') + '</ul>';
	document.getElementById('state').innerHTML = "Loaded";
}

function readUploadedFile(inputFile) {
	const temporaryFileReader = new FileReader();
	return new Promise((resolve, reject) => {
	  temporaryFileReader.onerror = () => {
		temporaryFileReader.abort();
		reject(new DOMException("Problem parsing input file."));
	  };
	  temporaryFileReader.onload = () => {
		resolve(temporaryFileReader.result);
	  };
	  temporaryFileReader.readAsArrayBuffer(inputFile);
	});
};
