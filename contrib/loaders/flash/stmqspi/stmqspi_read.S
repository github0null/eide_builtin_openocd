/* SPDX-License-Identifier: GPL-2.0-or-later */

/***************************************************************************
 *   Copyright (C) 2019 by Andreas Bolsch                                  *
 *   andreas.bolsch@mni.thm.de                                             *
 ***************************************************************************/

	.text
	.syntax unified
	.cpu cortex-m0
	.thumb
	.thumb_func

/* Params:
 * r0 - total count (bytes), remaining bytes (out, 0 means successful)
 * r1 - flash page size
 * r2 - address offset into flash
 * r3 - QSPI io_base
 * r8 - fifo start
 * r9 - fifo end + 1

 * Clobbered:
 * r4 - wp
 * r5 - address of QSPI_DR
 * r7 - tmp
 */

#include "../../../../src/flash/nor/stmqspi.h"

	.macro	qspi_abort
	movs	r5, #(1<<SPI_ABORT)			/* abort bit mask */
	ldr		r7, [r3, #QSPI_CR]			/* get QSPI_CR register */
	orrs	r7, r7, r5					/* set abort bit */
	str		r7, [r3, #QSPI_CR]			/* store new CR register */
	.endm

	.macro	wait_busy
0:
	ldr		r7, [r3, #QSPI_SR]			/* load status */
	lsrs	r7, r7, #(SPI_BUSY+1)		/* shift BUSY into C */
	bcs		0b							/* loop until BUSY cleared */
	movs	r7, #(1<<SPI_TCF)			/* TCF bitmask */
	str		r7, [r3, #QSPI_FCR]			/* clear TCF flag */
	.endm

start:
	subs	r0, r0, #1					/* decrement count for DLR */
	subs	r1, r1, #1					/* page size mask and for DLR */
	ldr		r4, wp						/* load wp */
start_read:
	qspi_abort							/* start in clean state */
	movs	r5, #QSPI_DR				/* load QSPI_DR address offset */
	adds	r5, r5, r3					/* address of QSPI_DR */
	wait_busy
	mov		r7, r2						/* get current start address */
	orrs	r7, r7, r1					/* end of current page */
	subs	r7, r7, r2					/* count-1 to end of page */
	cmp		r7, r0						/* if this count <= remaining */
	bls		write_dlr					/* then read to end of page */
	mov		r7, r0						/* else read all remaining */
write_dlr:
	str		r7, [r3, #QSPI_DLR]			/* size-1 in DLR register */
	ldr		r7, ccr_page_read			/* CCR for page read */
	str		r7, [r3, #QSPI_CCR]			/* initiate transfer */
	str		r2, [r3, #QSPI_AR]			/* store SPI start address */
	ldr		r7, [r3, #QSPI_SR]			/* wait for command startup */
read_loop:
	ldrb	r7, [r5]					/* read next byte from DR */
	strb	r7, [r4, #0]				/* write next byte */
	adds	r4, r4, #1					/* increment internal wp */
	cmp		r4, r9						/* internal wp beyond end? */
	blo		wait_fifo					/* if no, then ok */
	mov		r4, r8						/* else wrap around */
wait_fifo:
	ldr		r7, rp						/* get rp */
	cmp		r7, #0						/* if rp equals 0 */
	beq		exit						/* then abort */
	cmp		r4, r7						/* check if fifo full */
	beq		wait_fifo					/* wait until not full */
	adr		r7, wp						/* get address of wp */
	str		r4, [r7]					/* store updated wp */
	adds	r2, r2, #1					/* increment address */
	subs	r0, r0, #1					/* decrement (count-1) */
	bmi		exit						/* stop if no data left */
	tst		r2, r1						/* page end ? */
	bne		read_loop					/* if not, then next byte */
page_end:
	bal		start_read					/* then next page */

exit:
	adds	r0, r0, #1					/* increment count due to the -1 */
	qspi_abort							/* to idle state */

	.align	2							/* align to word, bkpt is 4 words */
	bkpt	#0							/* before code end for exit_point */
	.align	2							/* align to word */

	.space	4							/* not used */
	.space	4							/* not used */
	.space	4							/* not used */
	.space	4							/* not used */

	.space	4							/* not used */
	.space	4							/* not used */
	.space	4							/* not used */
	.space	4							/* not used */

	.space	4							/* not used */
ccr_page_read:
	.space	4							/* QSPI_CCR value for read command */
	.space	4							/* not used */
	.space	4							/* not used */

	.equ wp, .							/* wp, uint32_t */
	.equ rp, wp + 4						/* rp, uint32_t */
	.equ buffer, rp + 4					/* buffer follows right away */
