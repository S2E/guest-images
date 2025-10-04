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
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/sched.h>
#include <linux/kprobes.h>
#include <linux/slab.h>
#include <linux/binfmts.h>
#include <asm/processor.h>
#include <linux/dcache.h>
#include <linux/namei.h>
#include <linux/mman.h>
#include <linux/fs.h>
#include <linux/kasan.h>
#include <linux/printk.h>
#include <linux/version.h>

#include <linux/preempt.h>

#include <linux/mm_types.h>

#include <linux/elf.h>
#include <linux/elf-randomize.h>

#include <linux/sched/task_stack.h>

#include <s2e/s2e.h>
#include <s2e/linux/linux_monitor.h>

#include "s2e-kprobe.h"

#ifdef S2E_ENABLED
#define print(fmt, arg...) s2e_printf(fmt, ##arg)
//#define print(fmt, arg...) printk(KERN_INFO fmt, ##arg)
#else
#define print(fmt, arg...) printk(KERN_INFO fmt, ##arg)
#endif //S2E_ENABLED

struct task_struct *s2e_current;
struct nameidata;

/* mprotect */
static int handler_mprotect_entry(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct mprotect_data *data = (struct mprotect_data *) p->data;
    data->start = regs->di;
    data->len = regs->si;
    data->prot = regs->dx;

#ifdef S2E_DEBUG
    print("%d) mprotect entry: %lx, flags = 0x%lx start = 0x%lx, len = %lx, prot = 0x%lx\n", current->pid, regs->ip, regs->flags, data->start, data->len, data->prot);
#endif
    return 0;
}

static int handler_mprotect_return(struct kretprobe_instance *p, struct pt_regs *regs) {
    unsigned long retval = regs_return_value(regs);
    struct mprotect_data *data = (struct mprotect_data *) p->data;
    if (!retval) {
#ifdef S2E_ENABLED
        s2e_linux_mprotect(current, data->start, data->len, data->prot);
#endif
    }
#ifdef S2E_DEBUG
    print("%d) mprotect return: start = 0x%lx, len = %lx, prot = 0x%lx, retval = %lx\n", current->pid, data->start, data->len, data->prot, retval);
#endif
    return 0;
}


/* panic */
//TODO panic needs some fixing
static int handler_panic_entry(struct kprobe *p, struct pt_regs *regs) {
    const char *fmt = (const char *)regs->di;
    static char buf[1024];
    va_list args;
    //va_start(args, fmt);
    /*vsnprintf(buf, sizeof(buf), fmt, args);*/
    //va_end(args);

#ifdef S2E_ENABLED
    /*s2e_linux_kernel_panic(buf, sizeof(buf));*/
#endif
    return 0;
}

/* process_exit */
static int handler_process_exit_entry(struct kprobe *p, struct pt_regs *regs) {
#ifdef S2E_DEBUG
    print("process_exit: %d detected process %s exit with code %d\n", current->pid, current->comm, current->exit_code);
#endif
#ifdef S2E_ENABLED
    s2e_linux_thread_exit(current, current->exit_code);
    if (atomic_read(&current->signal->live) == 0)
        s2e_linux_process_exit(current, current->exit_code);
#endif
    return 0;
}

/* trap */
static int handler_trap_entry(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct trap_data *data = (struct trap_data *) p->data;
    data->trapnr = regs->cx;
    data->signr = regs->r8;
    data->regs = (struct pt_regs *)regs->di;
    data->error_code = regs->si;
#ifdef S2E_DEBUG
    print("trap entry: %d detected process %s\n", current->pid, current->comm);
#endif
    return 0;
}

static int handler_trap_return(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct trap_data *data = (struct trap_data *) p->data;
#ifdef S2E_DEBUG
    print("trap return: %d detected process %s, signr %d, error_code %ld\n", current->pid, current->comm, data->signr, data->error_code);
#endif
#ifdef S2E_ENABLED
    s2e_linux_trap(current, task_pt_regs(current)->ip, data->trapnr, data->signr, data->error_code);
#endif
    return 0;
}


/* segfault */
static int handler_segfault_entry(struct kprobe *p, struct pt_regs *regs) {
    siginfo_t *info;
    struct task_struct *tsk;
    tsk = (struct task_struct *) regs->dx;
    info = (siginfo_t *) regs->si;
#ifdef S2E_ENABLED
    s2e_linux_segfault(current, task_pt_regs(tsk)->ip, (uint64_t)info->si_addr, 0);
#endif
#ifdef S2E_DEBUG
    print("segfault entry: %d detected process %s, ip %lx, si_addr %llx\n", current->pid, current->comm, task_pt_regs(tsk)->ip, (uint64_t) info->si_addr);
#endif
    return 0;
}

/* process_load */
static int handler_process_load_entry(struct kprobe *p, struct pt_regs *regs) {
#ifdef S2E_DEBUG
    print("process_load entry: %d detected process %s, interp %s\n", current->pid, current->comm, ((struct linux_binprm *) regs->di)->interp);
#endif
#ifdef S2E_ENABLED
    s2e_linux_process_load(current, ((struct linux_binprm *)regs->di)->interp);
#endif
    return 0;
}

/* mmap */
static int handler_mmap_entry(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct mmap_data *data = (struct mmap_data *) p->data;
    data->len = (unsigned long)regs->dx;
    data->prot = (unsigned long)regs->cx;
    data->flag = (unsigned long)regs->r8;
    data->pgoff = (unsigned long)regs->r9;
#ifdef S2E_DEBUG
    print("mmap entry: %d detected process %s\n", current->pid, current->comm);
#endif
    return 0;
}

static int handler_mmap_return(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct mmap_data *data = (struct mmap_data *) p->data;
    unsigned long retval = regs_return_value(regs);

    if (retval != -1) { //TODO add check for s2e_monitor loaded
#ifdef S2E_ENABLED
       s2e_linux_mmap(current, retval, data->len, data->prot, data->flag, data->pgoff);
#endif
#ifdef S2E_DEBUG
    print("%d) %s mmap: address=%lx, size=%ld, prot=%lx, flag=%lx, pgoff=%lx\n", current->pid, current->comm, retval, data->len, data->prot, data->flag, data->pgoff);
#endif
    }
    return 0;
}

/* unmap */
static int handler_unmap_entry(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct unmap_data *data = (struct unmap_data *) p->data;
    data->start = regs->cx;
    data->end = regs->r8;
    return 0;
}

static int handler_unmap_return(struct kretprobe_instance *p, struct pt_regs *regs) {
    struct unmap_data *data = (struct unmap_data *) p->data;
#ifdef S2E_ENABLED
    if (data->start < data->end)
        s2e_linux_unmap(current, data->start, data->end);
    else
        s2e_linux_unmap(current, data->end, data->start);
#endif
#ifdef S2E_DEBUG
    print("unmap return: %d detected process %s, start=0x%lx, end=0x%lx\n", current->pid,
            current->comm, data->start, data->end);
#endif
    return 0;
}

/* module_load */
static int handler_module_load_entry(struct kretprobe_instance *p, struct pt_regs *regs) {
   struct module_load_data *data = (struct module_load_data *) p->data;

   print("module_load entry\n");

   data->bprm = (struct linux_binprm *)regs->di;

   return 0;
}

static int handler_module_load_return(struct kretprobe_instance *p, struct pt_regs *regs) {
    unsigned long retval = regs_return_value(regs);

    struct module_load_data *data = (struct module_load_data *) p->data;
    struct task_struct *task = current;
    struct mm_struct *mm = task->mm;
    int i = 0;

    // interpreter-related data
    int interp_phnum = 0;
    size_t interp_phdr_size = 0;
    struct elf_phdr *interp_phdata = NULL;
    struct S2E_LINUXMON_PHDR_DESC *interp_phdr  = NULL;
    uint64_t interp_e_entry = 0;

    // binary-related data
    int bin_phnum = 0;
    size_t bin_phdr_size = 0;
    struct elfhdr *bin_ex = NULL;
    struct elf_phdr *bin_ppnt, *bin_phdata = NULL;
    struct S2E_LINUXMON_PHDR_DESC *bin_phdr = NULL;

    char *name_interp_ptr = NULL;
    char *name_binary_ptr = NULL;

#ifdef S2E_DEBUG
    print("module_load return: %d detected process %s\n", current->pid,
            current->comm);
#endif

    if (retval != 0) return retval;


    bin_ex = (struct elfhdr *) data->bprm->buf;
    preempt_enable();
    bin_phdata = load_elf_phdrs(bin_ex, data->bprm->file);
    preempt_disable();
    bin_phnum = bin_ex->e_phnum;
    bin_phdr_size = sizeof(*bin_phdr) * bin_phnum;
    bin_phdr = kmalloc(bin_phdr_size, GFP_ATOMIC);

    if (!bin_phdr) {
        goto fail_bin_phdr;
    }

    memset(bin_phdr, 0, bin_phdr_size);

    // Gather information related to the interpreter module - old load_elf_interp
    for (i = 0, bin_ppnt = bin_phdata; i < bin_phnum; i++, bin_ppnt++) {
        // if not PT_INTERP continue
        if (bin_ppnt->p_type != PT_INTERP) {
            continue;
        }

        preempt_enable();
        interp_phdata = get_interpreter_phdr(data->bprm, bin_ppnt,
                &interp_phnum, &name_interp_ptr, &interp_e_entry);
        preempt_disable();

        if (!interp_phdata) {
            goto fail_interp_phdata;
        }
        else {
            print("name_interp_ptr %s\n", name_interp_ptr);
        }
        break;
    }

    if (mm->exe_file) {
      name_binary_ptr = get_fullpath(&mm->exe_file->f_path);
      print("name_binary_ptr %s\n", name_binary_ptr);
    }


    interp_phdr_size = sizeof(*interp_phdr) * interp_phnum;
    interp_phdr = kmalloc(interp_phdr_size, GFP_ATOMIC);

    if (!interp_phdr) {
        goto fail_interp_phdr;
    }

    if (interp_phdata) {
        // if interpreter is available and we successfully loaded its header, let's retrieve the info for s2e
        retrieve_info_from_header(interp_phdata, interp_phnum, interp_phdr, name_interp_ptr);

#ifdef S2E_DEBUG
        print_phdr_info(interp_phdr, interp_phnum);
#endif
#ifdef S2E_ENABLED
        s2e_linux_module_load(name_interp_ptr, current, interp_e_entry, interp_phdr, interp_phdr_size);
#endif
    }

    // retrieve info for the amin binary to be loaded for s2e
    retrieve_info_from_header(bin_phdata, bin_phnum, bin_phdr, name_binary_ptr);
#ifdef S2E_DEBUG
    print_phdr_info(bin_phdr, bin_phnum);
#endif
#ifdef S2E_ENABLED
    s2e_linux_module_load(name_binary_ptr, current, bin_ex->e_entry, bin_phdr, bin_phdr_size);
#endif

    kfree(interp_phdr);
fail_interp_phdr:
    kfree(name_binary_ptr);
    kfree(interp_phdata);
fail_interp_phdata:
    kfree(name_interp_ptr);
    kfree(bin_phdr);
fail_bin_phdr:
    return retval;

}

// This function return the program header for the interpreter of the main binary if found, NULL otherwise
static struct elf_phdr * get_interpreter_phdr(struct linux_binprm *bprm, struct elf_phdr *bin_ppnt, int *phrnum, char **name_interp_ptr, uint64_t *e_entry) {
    int retval = 0;
    struct file *interp = NULL;
    char *bin_interpreter = NULL;
    struct elfhdr *interp_ex = NULL;
    struct elf_phdr *interp_phdata = NULL;

    struct path path;

    *name_interp_ptr = NULL;

    // Allocate buffer for interpreter name
    bin_interpreter = kmalloc(bin_ppnt->p_filesz, GFP_ATOMIC);

    if (!bin_interpreter) {
        print("Allocation elf_interpreter failed\n");
        goto fail;
    }

    // Retrieve interpreter name from program header PT_INTERP entry
    if ((retval = elf_read(bprm->file, bin_interpreter, bin_ppnt->p_filesz, bin_ppnt->p_offset)) < 0) {
        goto fail_bin_interpreter;
    }

    // Open file associated to the name
    interp = open_exec(bin_interpreter);

    retval = PTR_ERR(interp);

    if (IS_ERR(interp))
        goto fail_bin_interpreter;

    would_dump(bprm, interp);

    // Allocate interpreter
    interp_ex = kmalloc(sizeof(*interp_ex), GFP_ATOMIC);

    if (!interp_ex) {
        goto fail_bin_interpreter;
    }

    // Load elf information
    retval = elf_read(interp, interp_ex, sizeof(*interp_ex), 0);

    if (retval < 0)
        goto fail_interp_ex;

    // Retrieve pointer to the program header for the interpreter
    interp_phdata = load_elf_phdrs(interp_ex, interp);
    *phrnum = interp_ex->e_phnum;
    *e_entry = interp_ex->e_entry;

    if (!kern_path(bin_interpreter, LOOKUP_FOLLOW, &path)) {
        *name_interp_ptr = get_fullpath(&path);
        print("name_interp_ptr %s\n", *name_interp_ptr);
    }


fail_interp_ex:
    kfree(interp_ex);
fail_bin_interpreter:
    kfree(bin_interpreter);
fail:
    return interp_phdata;
}

static unsigned long get_vma (char *module_name, unsigned long pgoff, struct S2E_LINUXMON_COMMAND_MEMORY_MAP *mmap_desc) {
    char *name_vm_area_ptr = NULL;
    char *name_vm_area_path = NULL;
    struct vm_area_struct *mmap = NULL;

#if LINUX_VERSION_CODE < KERNEL_VERSION(6,1,0)
    mmap = current->mm->mmap;
    do {
#else
    VMA_ITERATOR(vmi, current->mm, 0);
    rcu_read_lock();
    for_each_vma(vmi, mmap) {
#endif
            struct file *file = mmap->vm_file;

            if (!file)
                continue;

            name_vm_area_ptr = get_fullpath(&file->f_path);

            if (!name_vm_area_ptr)
                continue;

            if(module_name && (strcmp(module_name, name_vm_area_ptr) == 0) && mmap->vm_pgoff == (pgoff>>PAGE_SHIFT)) {
                unsigned long res;
                mmap_desc->address = mmap->vm_start;
                mmap_desc->size = mmap->vm_end - mmap->vm_start;
                mmap_desc->prot = mmap->vm_page_prot.pgprot;
                mmap_desc->flag = mmap->vm_flags;
                mmap_desc->pgoff = mmap->vm_pgoff<<PAGE_SHIFT;

                kfree(name_vm_area_path);
                res = mmap->vm_start;
                rcu_read_unlock();
                return res;
            }
            kfree(name_vm_area_path);

#if LINUX_VERSION_CODE < KERNEL_VERSION(6,1,0)
    } while ((mmap = mmap->vm_next) != NULL);
#else
    }
#endif
    return 0;
}

// Given a struct elf_phdr *, it populates the S2E description structs to be sent to the LinuxMonitor
// If it's a PT_LOAD, we retrieve also the information about the vma  and populate also the substruct
static void retrieve_info_from_header (struct elf_phdr *phdr, int phnum, struct S2E_LINUXMON_PHDR_DESC *s2e_phdr, char *module_name) {
    int i = 0;
    struct elf_phdr *ppnt_tmp = NULL;
    struct S2E_LINUXMON_PHDR_DESC *s2e_tmp = NULL;

    for (i = 0, ppnt_tmp = phdr; i < phnum; ++i, ++ppnt_tmp) {
        s2e_tmp = &s2e_phdr[i];
        s2e_tmp->index = i;
        s2e_tmp->p_type = ppnt_tmp->p_type;
        s2e_tmp->p_offset = ppnt_tmp->p_offset;
        s2e_tmp->p_vaddr = ppnt_tmp->p_vaddr;
        s2e_tmp->p_paddr = ppnt_tmp->p_paddr;
        s2e_tmp->p_filesz = ppnt_tmp->p_filesz;
        s2e_tmp->p_memsz = ppnt_tmp->p_memsz;
        s2e_tmp->p_flags = ppnt_tmp->p_flags;
        s2e_tmp->p_align = ppnt_tmp->p_align;

        if (ppnt_tmp->p_type == PT_LOAD) {
            s2e_tmp->vma = get_vma(module_name, s2e_tmp->p_offset, &s2e_tmp->mmap);
        }
        else {
            s2e_tmp->vma = 0;
        }
    }
}

#ifdef S2E_DEBUG
// Dump the collected data for debug
static void print_phdr_info(struct S2E_LINUXMON_PHDR_DESC *phdr, int phnum)  {
    int i = 0;
    struct S2E_LINUXMON_PHDR_DESC *ppnt_tmp = NULL;
    for (i = 0; i < phnum; ++i) {
        ppnt_tmp = &phdr[i];
        print("-----------%lld------------\n", ppnt_tmp->index);
        print("Type %llx\n", ppnt_tmp->p_type);
        print("Offset %llx\n", ppnt_tmp->p_offset);
        print("Vaddr %llx\n", ppnt_tmp->p_vaddr);
        print("Paddr %llx\n", ppnt_tmp->p_paddr);
        print("Filesz %llx\n", ppnt_tmp->p_filesz);
        print("Memsz %llx\n", ppnt_tmp->p_memsz);
        print("Flags %llx\n", ppnt_tmp->p_flags);
        print("Align %llx\n", ppnt_tmp->p_align);
        print("VM Address %llx\n", ppnt_tmp->vma);

        if (ppnt_tmp->p_type == PT_LOAD) {
            print("MmapAddress %llx\n", ppnt_tmp->mmap.address);
            print("MmapSize %llx\n", ppnt_tmp->mmap.size);
            print("MmapProt %llx\n", ppnt_tmp->mmap.prot);
            print("MmapFlag %llx\n", ppnt_tmp->mmap.flag);
            print("MmapPgoff %llx\n", ppnt_tmp->mmap.pgoff);
        }
        print("---------------------------\n");
    }
}
#endif

// Given a relative path, it finds the full path. If it's a symlink, it follows it and return the real path
// It is used to split the allocated segments from vm_area_struct of the current process between process and intepreter
static char * get_fullpath(struct path *path) {
    char *pathname, *tmp, *retval = NULL;
    int size = 0;
    pathname = kmalloc(PATH_MAX, GFP_ATOMIC);

    if (!pathname)
        return NULL;

    tmp = d_path(path, pathname, PATH_MAX-1);

    size = sizeof(char) * strlen(tmp);

    retval  = kmalloc(size+1, GFP_ATOMIC);

    strncpy(retval, tmp, size);

    kfree(pathname);

    return retval;
}

static int handler_elf_map_entry (struct kretprobe_instance *p, struct pt_regs *regs) {
#ifdef S2E_DEBUG
    print("elf map entry: %d detected process %s exit with code %d\n", current->pid,
            current->comm, current->exit_code);
#endif
    return 0;
}

static int handler_elf_map_return (struct kretprobe_instance *p, struct pt_regs *regs) {
    unsigned long retval = regs_return_value(regs);
#ifdef S2E_DEBUG
    print("elf map return: %d detected process %s exit with code %d, return %lx\n", current->pid,
            current->comm, current->exit_code, retval);
#endif
    return 0;
}

static int handler_schedule_return (struct kretprobe_instance *p, struct pt_regs *regs) {
    s2e_current = current;
#if 0
    print("schedule return: context switched to %d", s2e_current->pid);
#endif
    return 0;
}

static int handler_switch_to_entry(struct kprobe *p, struct pt_regs *regs) {
    struct task_struct *prev = (struct task_struct *) regs->di;
    struct task_struct *next = (struct task_struct *) regs->si;
#ifdef S2E_DEBUG
    /*print("%d) task switching prev=%lx and next=%lx", current->pid, prev, next);*/
#endif

#ifdef S2E_ENABLED
    s2e_linux_task_switch(prev, next);
#endif
    return 0;
}


static int __init s2e_init(void) {
    int ret;
    char const *name;
    uint64_t task_struct_pid_offset = offsetof(struct task_struct, pid);
    uint64_t task_struct_tgid_offset = offsetof(struct task_struct, tgid);
    s2e_current = current;

    if (num_online_cpus() > 1) {
        print("LinuxMonitor only supports single-CPU systems\n");
        return 1;
    }

    print("offset %lx, START_KERNEL %lx, task_struct_pid_offset %lld, task_struct_tgid_offset %lld\n", PAGE_OFFSET, __START_KERNEL, task_struct_pid_offset, task_struct_tgid_offset);

    ret = register_kretprobe(&kp_mprotect);

    if (ret < 0) {
        name = "mprotect";
        goto fail;
    }

    ret = register_kprobe(&kp_panic);

    if (ret < 0) {
        name = "panic";
        goto fail_panic;
    }

    ret = register_kprobe(&kp_process_exit);

    if (ret < 0) {
        name = "process_exit";
        goto fail_process_exit;
    }

    ret = register_kretprobe(&kp_trap);

    if (ret < 0) {
        name = "trap";
        goto fail_trap;
    }

    ret = register_kprobe(&kp_segfault);

    if (ret < 0) {
        name = "segfault";
        goto fail_segfault;
    }

    ret = register_kprobe (&kp_load_process);

    if (ret < 0) {
        name = "process_load";
        goto fail_load_process;
    }

    ret = register_kretprobe (&kp_mmap);

    if (ret < 0) {
        name = "mmap";
        goto fail_mmap;
    }

    ret = register_kretprobe (&kp_unmap);

    if (ret < 0) {
        name = "unmap";
        goto fail_unmap;
    }

    ret = register_kretprobe (&kp_module_load);

    if (ret < 0) {
        name = "module_load";
        goto fail_module_load;
    }

    ret = register_kretprobe(&kp_elf_map);

    if (ret < 0) {
        name = "elf_map";
        goto fail_elf_map;
    }

    ret = register_kretprobe(&kp_schedule);

    if (ret < 0) {
        name = "__schedule";
        goto fail_schedule;
    }

    ret = register_kprobe(&kp_switch);

    if (ret < 0) {
        name = "__switch_to";
        goto fail_switch;
    }

    print("Planted kprobe\n");

#ifdef S2E_ENABLED
    s2e_linux_init(PAGE_OFFSET, __START_KERNEL);
#endif

    return 0;

fail_switch:
    unregister_kretprobe(&kp_schedule);
fail_schedule:
    unregister_kretprobe(&kp_elf_map);
fail_elf_map:
    unregister_kretprobe(&kp_module_load);
fail_module_load:
    unregister_kretprobe(&kp_unmap);
fail_unmap:
    unregister_kretprobe(&kp_mmap);
fail_mmap:
    unregister_kprobe(&kp_load_process);
fail_load_process:
    unregister_kprobe(&kp_segfault);
fail_segfault:
    unregister_kretprobe(&kp_trap);
fail_trap:
    unregister_kprobe(&kp_process_exit);
fail_process_exit:
    unregister_kprobe(&kp_panic);
fail_panic:
    unregister_kretprobe(&kp_mprotect);
fail:
    print("register_kretprobe for %s failed, returned %d\n", name, ret);
    return ret;
}

static void __exit s2e_exit(void) {
    unregister_kprobe(&kp_switch);
    print("kretprobe __kp_switch unregistered\n");
    unregister_kretprobe(&kp_schedule);
    print("kretprobe __schedule unregistered\n");
    unregister_kretprobe(&kp_elf_map);
    print("kretprobe elf_map unregistered\n");
    unregister_kretprobe(&kp_module_load);
    print("kretprobe module_load unregistered\n");
    unregister_kretprobe(&kp_unmap);
    print("kretprobe unmap unregistered\n");
    unregister_kretprobe(&kp_mmap);
    print("kretprobe mmap unregistered\n");
    unregister_kprobe(&kp_load_process);
    print("kprobe load process unregistered\n");
    unregister_kprobe(&kp_segfault);
    print("kprobe segfault unregistered\n");
    unregister_kretprobe(&kp_trap);
    print("kretprobe trap unregistered\n");
    unregister_kprobe(&kp_process_exit);
    print("kprobe process exit unregistered\n");
    unregister_kprobe(&kp_panic);
    print("kprobe panic unregistered\n");
    unregister_kretprobe(&kp_mprotect);
    print("kprobe mprotect unregistered\n");
}

module_init(s2e_init)
module_exit(s2e_exit)
MODULE_LICENSE("GPL");

