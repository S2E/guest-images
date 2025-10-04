/// Copyright (c) 2024 IBM Corporation
//
//  Author: Andrea Mambretti <amb@zurich.ibm.com>
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all
/// copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
/// SOFTWARE.

//#define S2E_DEBUG
#define S2E_ENABLED

#if ELF_EXEC_PAGESIZE > PAGE_SIZE
#define ELF_MIN_ALIGN    ELF_EXEC_PAGESIZE
#else
#define ELF_MIN_ALIGN    PAGE_SIZE
#endif

#ifdef S2E_DEBUG
static void print_phdr_info(struct S2E_LINUXMON_PHDR_DESC *, int phnum);
#endif
static void retrieve_info_from_header(struct elf_phdr *, int, struct S2E_LINUXMON_PHDR_DESC *, char *);
static struct elf_phdr *get_interpreter_phdr (struct linux_binprm *, struct elf_phdr *, int *, char **, uint64_t *);
static char *get_fullpath (struct path *);

/* __switch_to */
static int handler_switch_to_entry(struct kprobe *p, struct pt_regs *regs);

static struct kprobe kp_switch = {
    .symbol_name = "__switch_to",
    .pre_handler = handler_switch_to_entry,
};

/* __schedule */
static int handler_schedule_return(struct kretprobe_instance *p, struct pt_regs *regs);

static struct kretprobe kp_schedule = {
    .kp.symbol_name = "__schedule",
    .handler = handler_schedule_return,
};

/* elf_map start */
static int handler_elf_map_entry(struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_elf_map_return(struct kretprobe_instance *p, struct pt_regs *regs);

struct elf_map_data {
    unsigned long start;
};

static struct kretprobe kp_elf_map = {
#if LINUX_VERSION_CODE < KERNEL_VERSION(6,7,0)
    .kp.symbol_name = "elf_map",
#else
    .kp.symbol_name = "elf_load",
#endif
    .entry_handler = handler_elf_map_entry,
    .handler = handler_elf_map_return,
    .data_size = sizeof(struct elf_map_data),
    .maxactive = 20,
};
/* elf_map end */

/* module_load start */
static int handler_module_load_entry(struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_module_load_return(struct kretprobe_instance *p, struct pt_regs *regs);

struct module_load_data {
    struct linux_binprm *bprm;
};

static struct kretprobe kp_module_load = {
    .kp.symbol_name = "load_elf_binary",
    .entry_handler = handler_module_load_entry,
    .handler = handler_module_load_return,
    .data_size = sizeof(struct module_load_data),
    .maxactive = 20,
};
/* module_load end */

/* unmap */
static int handler_unmap_entry(struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_unmap_return(struct kretprobe_instance *p, struct pt_regs *regs);

struct unmap_data {
    unsigned long start;
    unsigned long end;
};

static struct kretprobe kp_unmap = {
    .kp.symbol_name = "unmap_region",
    .entry_handler = handler_unmap_entry,
    .handler = handler_unmap_return,
    .data_size = sizeof(struct unmap_data),
    .maxactive = 20,
};

/* mmap */
static int handler_mmap_entry (struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_mmap_return (struct kretprobe_instance *p, struct pt_regs *regs);

struct mmap_data {
   unsigned long len;
   unsigned long prot;
   unsigned long flag;
   unsigned long pgoff;
};

static struct kretprobe kp_mmap = {
    .kp.symbol_name = "vm_mmap_pgoff",
    .entry_handler = handler_mmap_entry,
    .handler = handler_mmap_return,
    .data_size = sizeof(struct mmap_data),
    .maxactive = 20,
};

/* process_load start */
static int handler_process_load_entry(struct kprobe *p, struct pt_regs *regs);

static struct kprobe kp_load_process = {
    .symbol_name = "load_elf_binary",
    .pre_handler = handler_process_load_entry,
};

/* process_load end */

/* mprotect  start */
static int handler_mprotect_entry(struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_mprotect_return(struct kretprobe_instance *p, struct pt_regs *regs);

struct mprotect_data {
    unsigned long start;
    size_t len;
    unsigned long prot;
};

static struct kretprobe kp_mprotect = {
    .kp.symbol_name    = "do_mprotect_pkey",
    .entry_handler = handler_mprotect_entry,
    .handler = handler_mprotect_return,
    .data_size = sizeof(struct mprotect_data),
    .maxactive = 20,
};
/* mprotect end */

/* panic start */
static int handler_panic_entry(struct kprobe *p, struct pt_regs *regs);

static struct kprobe kp_panic = {
    .symbol_name = "panic",
    .pre_handler = handler_panic_entry,
};

/* process_exit start */
static int handler_process_exit_entry(struct kprobe *p, struct pt_regs *regs);

static struct kprobe kp_process_exit = {
    .symbol_name = "do_task_dead",
    .pre_handler = handler_process_exit_entry,
};

/* process_exit end */


/* traps start */
static int handler_trap_entry(struct kretprobe_instance *p, struct pt_regs *regs);
static int handler_trap_return(struct kretprobe_instance *p, struct pt_regs *regs);

struct trap_data {
    int trapnr;
    int signr;
    struct pt_regs *regs;
    long error_code;
};

static struct kretprobe kp_trap = {
    .kp.symbol_name = "do_error_trap",
    .entry_handler = handler_trap_entry,
    .handler = handler_trap_return,
    .data_size = sizeof(struct trap_data),
    .maxactive = 20,
};


/* segfault start */
static int handler_segfault_entry(struct kprobe *p, struct pt_regs *regs);

static struct kprobe kp_segfault = {
    .symbol_name = "force_sig_info",
    .pre_handler = handler_segfault_entry,
};

static int elf_read(struct file *file, void *buf, size_t len, loff_t pos)
{
    ssize_t rv;

    rv = kernel_read(file, buf, len, &pos);
    if (unlikely(rv != len)) {
        return (rv < 0) ? rv : -EIO;
    }
    return 0;
}

/**
 * load_elf_phdrs() - load ELF program headers
 * @elf_ex:   ELF header of the binary whose program headers should be loaded
 * @elf_file: the opened ELF binary file
 *
 * Loads ELF program headers from the binary file elf_file, which has the ELF
 * header pointed to by elf_ex, into a newly allocated array. The caller is
 * responsible for freeing the allocated data. Returns an ERR_PTR upon failure.
 */
static struct elf_phdr *load_elf_phdrs(const struct elfhdr *elf_ex,
                       struct file *elf_file)
{
    struct elf_phdr *elf_phdata = NULL;
    int retval, err = -1;
    unsigned int size;

    /*
     * If the size of this structure has changed, then punt, since
     * we will be doing the wrong thing.
     */
    if (elf_ex->e_phentsize != sizeof(struct elf_phdr))
        goto out;

    /* Sanity check the number of program headers... */
    /* ...and their total size. */
    size = sizeof(struct elf_phdr) * elf_ex->e_phnum;
    if (size == 0 || size > 65536 || size > ELF_MIN_ALIGN)
        goto out;

    elf_phdata = kmalloc(size, GFP_NOWAIT);
    if (!elf_phdata)
        goto out;

    /* Read in the program headers */
    retval = elf_read(elf_file, elf_phdata, size, elf_ex->e_phoff);
    if (retval < 0) {
        err = retval;
        goto out;
    }

    /* Success! */
    err = 0;
out:
    if (err) {
        kfree(elf_phdata);
        elf_phdata = NULL;
    }
    return elf_phdata;
}


