/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/linkage.h>
#include <asm/asm.h>
#include <asm/bitsperlong.h>
#include <asm/kvm_vcpu_regs.h>
#include <asm/nospec-branch.h>
#include "run_flags.h"

#define WORD_SIZE (BITS_PER_LONG / 8)

#define VCPU_RAX	__VCPU_REGS_RAX * WORD_SIZE
#define VCPU_RCX	__VCPU_REGS_RCX * WORD_SIZE
#define VCPU_RDX	__VCPU_REGS_RDX * WORD_SIZE
#define VCPU_RBX	__VCPU_REGS_RBX * WORD_SIZE
/* Intentionally omit RSP as it's context switched by hardware */
#define VCPU_RBP	__VCPU_REGS_RBP * WORD_SIZE
#define VCPU_RSI	__VCPU_REGS_RSI * WORD_SIZE
#define VCPU_RDI	__VCPU_REGS_RDI * WORD_SIZE

#ifdef CONFIG_X86_64
#define VCPU_R8		__VCPU_REGS_R8  * WORD_SIZE
#define VCPU_R9		__VCPU_REGS_R9  * WORD_SIZE
#define VCPU_R10	__VCPU_REGS_R10 * WORD_SIZE
#define VCPU_R11	__VCPU_REGS_R11 * WORD_SIZE
#define VCPU_R12	__VCPU_REGS_R12 * WORD_SIZE
#define VCPU_R13	__VCPU_REGS_R13 * WORD_SIZE
#define VCPU_R14	__VCPU_REGS_R14 * WORD_SIZE
#define VCPU_R15	__VCPU_REGS_R15 * WORD_SIZE
#endif

	.text

/**
 * __vmx_vcpu_run - Run a vCPU via a transition to VMX guest mode
 * @vmx:	struct vcpu_vmx *
 * @regs:	unsigned long * (to guest registers)
 * @flags:	VMX_RUN_VMRESUME:	use VMRESUME instead of VMLAUNCH
 *		VMX_RUN_SAVE_SPEC_CTRL: save guest SPEC_CTRL into vmx->spec_ctrl
 *
 * Returns:
 *	0 on VM-Exit, 1 on VM-Fail
 */
ENTRY(__vmx_vcpu_run)
	push %_ASM_BP
	mov  %_ASM_SP, %_ASM_BP
#ifdef CONFIG_X86_64
	push %r15
	push %r14
	push %r13
	push %r12
#else
	push %edi
	push %esi
#endif
	push %_ASM_BX

	/* Save @vmx for SPEC_CTRL handling */
	push %_ASM_ARG1

	/* Save @flags for SPEC_CTRL handling */
	push %_ASM_ARG3

	/*
	 * Save @regs, _ASM_ARG2 may be modified by vmx_update_host_rsp() and
	 * @regs is needed after VM-Exit to save the guest's register values.
	 */
	push %_ASM_ARG2

	/* Copy @flags to BL, _ASM_ARG3 is volatile. */
	mov %_ASM_ARG3B, %bl

	lea (%_ASM_SP), %_ASM_ARG2
	call vmx_update_host_rsp

	/* Load @regs to RAX. */
	mov (%_ASM_SP), %_ASM_AX

	/* Check if vmlaunch or vmresume is needed */
	testb $VMX_RUN_VMRESUME, %bl

	/* Load guest registers.  Don't clobber flags. */
	mov VCPU_RBX(%_ASM_AX), %_ASM_BX
	mov VCPU_RCX(%_ASM_AX), %_ASM_CX
	mov VCPU_RDX(%_ASM_AX), %_ASM_DX
	mov VCPU_RSI(%_ASM_AX), %_ASM_SI
	mov VCPU_RDI(%_ASM_AX), %_ASM_DI
	mov VCPU_RBP(%_ASM_AX), %_ASM_BP
#ifdef CONFIG_X86_64
	mov VCPU_R8 (%_ASM_AX),  %r8
	mov VCPU_R9 (%_ASM_AX),  %r9
	mov VCPU_R10(%_ASM_AX), %r10
	mov VCPU_R11(%_ASM_AX), %r11
	mov VCPU_R12(%_ASM_AX), %r12
	mov VCPU_R13(%_ASM_AX), %r13
	mov VCPU_R14(%_ASM_AX), %r14
	mov VCPU_R15(%_ASM_AX), %r15
#endif
	/* Load guest RAX.  This kills the @regs pointer! */
	mov VCPU_RAX(%_ASM_AX), %_ASM_AX

	/* Check EFLAGS.ZF from 'testb' above */
	jz .Lvmlaunch

/*
 * If VMRESUME/VMLAUNCH and corresponding vmexit succeed, execution resumes at
 * the 'vmx_vmexit' label below.
 */
.Lvmresume:
	vmresume
	jmp .Lvmfail

.Lvmlaunch:
	vmlaunch
	jmp .Lvmfail

	_ASM_EXTABLE(.Lvmresume, .Lfixup)
	_ASM_EXTABLE(.Lvmlaunch, .Lfixup)

SYM_INNER_LABEL(vmx_vmexit, SYM_L_GLOBAL)

	/* Temporarily save guest's RAX. */
	push %_ASM_AX

	/* Reload @regs to RAX. */
	mov WORD_SIZE(%_ASM_SP), %_ASM_AX

	/* Save all guest registers, including RAX from the stack */
	__ASM_SIZE(pop) VCPU_RAX(%_ASM_AX)
	mov %_ASM_BX,   VCPU_RBX(%_ASM_AX)
	mov %_ASM_CX,   VCPU_RCX(%_ASM_AX)
	mov %_ASM_DX,   VCPU_RDX(%_ASM_AX)
	mov %_ASM_SI,   VCPU_RSI(%_ASM_AX)
	mov %_ASM_DI,   VCPU_RDI(%_ASM_AX)
	mov %_ASM_BP,   VCPU_RBP(%_ASM_AX)
#ifdef CONFIG_X86_64
	mov %r8,  VCPU_R8 (%_ASM_AX)
	mov %r9,  VCPU_R9 (%_ASM_AX)
	mov %r10, VCPU_R10(%_ASM_AX)
	mov %r11, VCPU_R11(%_ASM_AX)
	mov %r12, VCPU_R12(%_ASM_AX)
	mov %r13, VCPU_R13(%_ASM_AX)
	mov %r14, VCPU_R14(%_ASM_AX)
	mov %r15, VCPU_R15(%_ASM_AX)
#endif

	/* Clear return value to indicate VM-Exit (as opposed to VM-Fail). */
	xor %ebx, %ebx

.Lclear_regs:
	/*
	 * Clear all general purpose registers except RSP and RBX to prevent
	 * speculative use of the guest's values, even those that are reloaded
	 * via the stack.  In theory, an L1 cache miss when restoring registers
	 * could lead to speculative execution with the guest's values.
	 * Zeroing XORs are dirt cheap, i.e. the extra paranoia is essentially
	 * free.  RSP and RAX are exempt as RSP is restored by hardware during
	 * VM-Exit and RBX is explicitly loaded with 0 or 1 to hold the return
	 * value.
	 */
	xor %eax, %eax
	xor %ecx, %ecx
	xor %edx, %edx
	xor %esi, %esi
	xor %edi, %edi
	xor %ebp, %ebp
#ifdef CONFIG_X86_64
	xor %r8d,  %r8d
	xor %r9d,  %r9d
	xor %r10d, %r10d
	xor %r11d, %r11d
	xor %r12d, %r12d
	xor %r13d, %r13d
	xor %r14d, %r14d
	xor %r15d, %r15d
#endif

	/* "POP" @regs. */
	add $WORD_SIZE, %_ASM_SP

	/*
	 * IMPORTANT: RSB filling and SPEC_CTRL handling must be done before
	 * the first unbalanced RET after vmexit!
	 *
	 * For retpoline or IBRS, RSB filling is needed to prevent poisoned RSB
	 * entries and (in some cases) RSB underflow.
	 *
	 * eIBRS has its own protection against poisoned RSB, so it doesn't
	 * need the RSB filling sequence.  But it does need to be enabled, and a
	 * single call to retire, before the first unbalanced RET.
         */

	FILL_RETURN_BUFFER %_ASM_CX, RSB_CLEAR_LOOPS, X86_FEATURE_RSB_VMEXIT,\
			   X86_FEATURE_RSB_VMEXIT_LITE


	pop %_ASM_ARG2	/* @flags */
	pop %_ASM_ARG1	/* @vmx */

	call vmx_spec_ctrl_restore_host

	CLEAR_BRANCH_HISTORY_VMEXIT

	/* Put return value in AX */
	mov %_ASM_BX, %_ASM_AX

	pop %_ASM_BX
#ifdef CONFIG_X86_64
	pop %r12
	pop %r13
	pop %r14
	pop %r15
#else
	pop %esi
	pop %edi
#endif
	pop %_ASM_BP
	ret

.Lfixup:
	cmpb $0, kvm_rebooting
	jne .Lvmfail
	ud2
.Lvmfail:
	/* VM-Fail: set return value to 1 */
	mov $1, %_ASM_BX
	jmp .Lclear_regs

ENDPROC(__vmx_vcpu_run)


.section .text, "ax"

/**
 * vmread_error_trampoline - Trampoline from inline asm to vmread_error()
 * @field:	VMCS field encoding that failed
 * @fault:	%true if the VMREAD faulted, %false if it failed

 * Save and restore volatile registers across a call to vmread_error().  Note,
 * all parameters are passed on the stack.
 */
ENTRY(vmread_error_trampoline)
	push %_ASM_BP
	mov  %_ASM_SP, %_ASM_BP

	push %_ASM_AX
	push %_ASM_CX
	push %_ASM_DX
#ifdef CONFIG_X86_64
	push %rdi
	push %rsi
	push %r8
	push %r9
	push %r10
	push %r11
#endif
#ifdef CONFIG_X86_64
	/* Load @field and @fault to arg1 and arg2 respectively. */
	mov 3*WORD_SIZE(%rbp), %_ASM_ARG2
	mov 2*WORD_SIZE(%rbp), %_ASM_ARG1
#else
	/* Parameters are passed on the stack for 32-bit (see asmlinkage). */
	push 3*WORD_SIZE(%ebp)
	push 2*WORD_SIZE(%ebp)
#endif

	call vmread_error

#ifndef CONFIG_X86_64
	add $8, %esp
#endif

	/* Zero out @fault, which will be popped into the result register. */
	_ASM_MOV $0, 3*WORD_SIZE(%_ASM_BP)

#ifdef CONFIG_X86_64
	pop %r11
	pop %r10
	pop %r9
	pop %r8
	pop %rsi
	pop %rdi
#endif
	pop %_ASM_DX
	pop %_ASM_CX
	pop %_ASM_AX
	pop %_ASM_BP

	ret
ENDPROC(vmread_error_trampoline)
