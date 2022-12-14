/* SPDX-License-Identifier: GPL-2.0-or-later */

/***************************************************************************
 *   Copyright (C) 2012 by George Harris                                   *
 *   george@luminairecoffee.com                                            *
 ***************************************************************************/

	.text
	.syntax unified
	.cpu cortex-m3
	.thumb
	.thumb_func

/*
 * Params :
 * r0 = start address, status (out)
 * r1 = count
 * r2 = erase command
 * r3 = block size
 */

#define SSP_BASE_HIGH				0x4008
#define SSP_BASE_LOW				0x3000
#define SSP_CR0_OFFSET				0x00
#define SSP_CR1_OFFSET				0x04
#define SSP_DATA_OFFSET 			0x08
#define SSP_CPSR_OFFSET 			0x10
#define SSP_SR_OFFSET				0x0c

#define SSP_CLOCK_BASE_HIGH 		0x4005
#define SSP_CLOCK_BASE_LOW 			0x0000
#define SSP_BRANCH_CLOCK_BASE_HIGH 	0x4005
#define SSP_BRANCH_CLOCK_BASE_LOW	0x2000
#define SSP_BASE_CLOCK_OFFSET		0x94
#define SSP_BRANCH_CLOCK_OFFSET		0x700

#define IOCONFIG_BASE_HIGH			0x4008
#define IOCONFIG_BASE_LOW			0x6000
#define IOCONFIG_SCK_OFFSET			0x18c
#define IOCONFIG_HOLD_OFFSET		0x190
#define IOCONFIG_WP_OFFSET			0x194
#define IOCONFIG_MISO_OFFSET		0x198
#define IOCONFIG_MOSI_OFFSET		0x19c
#define IOCONFIG_CS_OFFSET			0x1a0

#define IO_BASE_HIGH 				0x400f
#define IO_BASE_LOW 				0x4000
#define IO_CS_OFFSET 				0xab
#define IODIR_BASE_HIGH 			0x400f
#define IODIR_BASE_LOW				0x6000
#define IO_CS_DIR_OFFSET 			0x14


setup: /* Initialize SSP pins and module */
	mov.w	r10, #IOCONFIG_BASE_LOW
	movt	r10, #IOCONFIG_BASE_HIGH
	mov.w	r8, #0xea
	str.w	r8, [r10, #IOCONFIG_SCK_OFFSET]		/* Configure SCK pin function */
	mov.w	r8, #0x40
	str.w	r8, [r10, #IOCONFIG_HOLD_OFFSET]	/* Configure /HOLD pin function */
	mov.w	r8, #0x40
	str.w	r8, [r10, #IOCONFIG_WP_OFFSET]		/* Configure /WP pin function */
	mov.w	r8, #0xed
	str.w	r8, [r10, #IOCONFIG_MISO_OFFSET]	/* Configure MISO pin function */
	mov.w	r8, #0xed
	str.w	r8, [r10, #IOCONFIG_MOSI_OFFSET]	/* Configure MOSI pin function */
	mov.w	r8, #0x44
	str.w	r8, [r10, #IOCONFIG_CS_OFFSET]		/* Configure CS pin function */

	mov.w	r10, #IODIR_BASE_LOW
	movt	r10, #IODIR_BASE_HIGH
	mov.w	r8, #0x800
	str 	r8, [r10, #IO_CS_DIR_OFFSET]		/* Set CS as output */
	mov.w	r10, #IO_BASE_LOW
	movt	r10, #IO_BASE_HIGH
	mov.w	r8, #0xff
	str.w	r8, [r10, #IO_CS_OFFSET]			/* Set CS high */

	mov.w 	r10, #SSP_CLOCK_BASE_LOW
	movt 	r10, #SSP_CLOCK_BASE_HIGH
	mov.w 	r8, #0x0000
	movt 	r8, #0x0100
	str.w 	r8, [r10, #SSP_BASE_CLOCK_OFFSET] 	/* Configure SSP0 base clock (use 12 MHz IRC) */

	mov.w 	r10, #SSP_BRANCH_CLOCK_BASE_LOW
	movt 	r10, #SSP_BRANCH_CLOCK_BASE_HIGH
	mov.w 	r8, #0x01
	str.w 	r8, [r10, #SSP_BRANCH_CLOCK_OFFSET] /* Configure (enable) SSP0 branch clock */

	mov.w 	r10, #SSP_BASE_LOW
	movt	r10, #SSP_BASE_HIGH
	mov.w 	r8, #0x07
	str.w 	r8, [r10, #SSP_CR0_OFFSET] 			/* Set clock postscale */
	mov.w 	r8, #0x02
	str.w 	r8, [r10, #SSP_CPSR_OFFSET] 		/* Set clock prescale */
	str.w 	r8, [r10, #SSP_CR1_OFFSET] 			/* Enable SSP in SPI mode */
write_enable:
	bl 		cs_down
	mov.w 	r9, #0x06 		/* Send the write enable command */
	bl 		write_data
	bl 		cs_up

	bl 		cs_down
	mov.w 	r9, #0x05 		/* Get status register */
	bl 		write_data
	mov.w 	r9, #0x00 		/* Dummy data to clock in status */
	bl 		write_data
	bl 		cs_up

	tst 	r9, #0x02 		/* If the WE bit isn't set, we have a problem. */
	beq 	error
erase:
	bl 		cs_down
	mov.w 	r9, r2 			/* Send the erase command */
	bl 		write_data
write_address:
	lsr 	r9, r0, #16 	/* Send the current 24-bit write address, MSB first */
	bl 		write_data
	lsr 	r9, r0, #8
	bl 		write_data
	mov.w 	r9, r0
	bl 		write_data
	bl 		cs_up
wait_flash_busy:			/* Wait for the flash to finish the previous erase */
	bl 		cs_down
	mov.w 	r9, #0x05 		/* Get status register */
	bl 		write_data
	mov.w 	r9, #0x00 		/* Dummy data to clock in status */
	bl 		write_data
	bl 		cs_up
	tst 	r9, #0x01 		/* If it isn't done, keep waiting */
	bne 	wait_flash_busy

	subs	r1, r1, #1					/* decrement count */
	cbz		r1, exit 					/* Exit if we have written everything */
	add 	r0, r3						/* Move the address up by the block size */
	b 		write_enable 				/* Start a new block erase */
write_data: 							/* Send/receive 1 byte of data over SSP */
	mov.w	r10, #SSP_BASE_LOW
	movt	r10, #SSP_BASE_HIGH
	str.w 	r9, [r10, #SSP_DATA_OFFSET]	/* Write supplied data to the SSP data reg */
wait_transmit:
	ldr 	r9, [r10, #SSP_SR_OFFSET] 	/* Check SSP status */
	tst 	r9, #0x0010					/* Check if BSY bit is set */
	bne 	wait_transmit 				/* If still transmitting, keep waiting */
	ldr 	r9, [r10, #SSP_DATA_OFFSET]	/* Load received data */
	bx 		lr 							/* Exit subroutine */
cs_up:
	mov.w 	r8, #0xff
	b 		cs_write
cs_down:
	mov.w 	r8, #0x0000
cs_write:
	mov.w 	r10, #IO_BASE_LOW
	movt	r10, #IO_BASE_HIGH
	str.w 	r8, [r10, #IO_CS_OFFSET]
	bx 		lr
error:
	movs	r0, #0
exit:
	bkpt 	#0x00

	.end
