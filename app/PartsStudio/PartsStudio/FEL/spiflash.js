async function backup_sram() {

}

async function restore_sram() {
	
}

/*
 * Configure pin function on a GPIO port
 */
async function gpio_set_cfgpin() {

}

async function spi_is_sun6i() {

}

/*
 * Init the SPI0 controller and setup pins muxing.
 */
async function spi0_init() {

}

async function aw_fel_remotefunc_execute() {

}

async function aw_fel_remotefunc_prepare_spi_batch_data_transfer() {

}

async function prepare_spi_batch_data_transfer() {

}

async function aw_fel_spiflash_info() {

}

async function aw_fel_spiflash_read() {
	
}

async function aw_fel_spiflash_write() {
	
}

/*****************************************************************************/
// SPI Flash Defines


const PA =                          (0);
const PB =                          (1);
const PC =                          (2);

const CCM_SPI0_CLK =               (0x01C20000 + 0xA0);
const CCM_AHB_GATING0 =            (0x01C20000 + 0x60);
const CCM_AHB_GATE_SPI0 =          (1 << 20);
const SUN6I_BUS_SOFT_RST_REG0 =    (0x01C20000 + 0x2C0);
const SUN6I_SPI0_RST =             (1 << 20);

const SUNXI_GPC_SPI0 =              (3);
const SUN50I_GPC_SPI0 =             (4);

const SUN4I_CTL_ENABLE =           (1 << 0);
const SUN4I_CTL_MASTER =           (1 << 1);
const SUN4I_CTL_TF_RST =           (1 << 8);
const SUN4I_CTL_RF_RST =           (1 << 9);
const SUN4I_CTL_XCH =              (1 << 10);

const SUN6I_TCR_XCH =              (1 << 31);

const SUN4I_SPI0_CCTL =            (0x01C05000 + 0x1C);
const SUN4I_SPI0_CTL =             (0x01C05000 + 0x08);
const SUN4I_SPI0_RX =              (0x01C05000 + 0x00);
const SUN4I_SPI0_TX =              (0x01C05000 + 0x04);
const SUN4I_SPI0_FIFO_STA =        (0x01C05000 + 0x28);
const SUN4I_SPI0_BC =              (0x01C05000 + 0x20);
const SUN4I_SPI0_TC =              (0x01C05000 + 0x24);

const SUN6I_SPI0_CCTL =           (0x01C68000 + 0x24);
const SUN6I_SPI0_GCR =            (0x01C68000 + 0x04);
const SUN6I_SPI0_TCR =            (0x01C68000 + 0x08);
const SUN6I_SPI0_FIFO_STA =       (0x01C68000 + 0x1C);
const SUN6I_SPI0_MBC =            (0x01C68000 + 0x30);
const SUN6I_SPI0_MTC =            (0x01C68000 + 0x34);
const SUN6I_SPI0_BCC =            (0x01C68000 + 0x38);
const SUN6I_SPI0_TXD =            (0x01C68000 + 0x200);
const SUN6I_SPI0_RXD =            (0x01C68000 + 0x300);

const CCM_SPI0_CLK_DIV_BY_2 =     (0x1000);
const CCM_SPI0_CLK_DIV_BY_4 =     (0x1001);
const CCM_SPI0_CLK_DIV_BY_6 =     (0x1002);

/*****************************************************************************/