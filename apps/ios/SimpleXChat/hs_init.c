//
//  hs_init.c
//  SimpleXChat
//
//  Created by Evgeny on 22/11/2023.
//  Copyright © 2023 SimpleX Chat. All rights reserved.
//

#include "hs_init.h"
#include <string.h>

extern void hs_init_with_rtsopts(int * argc, char **argv[]);

void haskell_init(int nse, const char *eventlog, const char *heap_profile) {
    // setup static arena for bump allocation and passing to RTS
    char *argv[32] = {0,};
    int argc = 0; // number of arguments used so far, always stands at the first NULL in argv
    // common args
    if (nse) {
      argv[argc++] = "simplex-nse"; // fake program name
    } else {
      argv[argc++] = "simplex";
    }
    argv[argc++] = "+RTS"; // start adding RTS options
    if (nse) {
      argv[argc++] = "-S"; // spam stdout with GC stats
      argv[argc++] = "-A1m"; // chunk size for new allocations (less frequent GC)
      argv[argc++] = "-H2m"; // larger heap size on start (faster boot)
      argv[argc++] = "-M12m"; // hard limit on heap
      argv[argc++] = "-F0.5"; // heap growth triggering GC
      argv[argc++] = "-Fd1"; // memory return
    } else {
      argv[argc++] = "-T"; // make GC counters available from inside the program
      argv[argc++] = "-A64m"; // chunk size for new allocations (less frequent GC)
      argv[argc++] = "-H64m"; // larger heap size on start (faster boot)
    }
    // argv[argc++] = "-M8G"; // keep memory usage under 8G, collecting more aggressively when approaching it (and crashing sooner rather than taking down the whole system)
    if (eventlog) {
        static char ol[1024] = "-ol";
        (void)strncpy(&ol[3], eventlog, sizeof(ol) - 3);
        argv[argc++] = ol;
        argv[argc++] = "-l-agu"; // collect GC and user events
    }
    if (heap_profile) {
        static char po[1024] = "-po";
        (void)strncpy(&po[3], heap_profile, sizeof(po) - 3);
        argv[argc++] = po; // adds ".hp" extension
        argv[argc++] = "-hT"; // emit heap profile by closure type
    }
    if (nse) {
      argv[argc++] = "-c"; // compacting garbage collector
    } else {
      int non_moving_gc = !heap_profile; // not compatible with heap profile
      if (non_moving_gc) argv[argc++] = "-xn";
    }
    // wrap args as expected by RTS
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
}

void haskell_init_nse(void) {
    int argc = 7;
    char *argv[] = {
        "simplex",
        "+RTS", // requires `hs_init_with_rtsopts`
        "-A1m", // chunk size for new allocations
        "-H1m", // initial heap size
        "-F0.5", // heap growth triggering GC
        "-Fd1", // memory return
        "-c", // compacting garbage collector
        0
    };
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
}
