#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

namespace single_instance {

bool Acquire();

void TagWindow(HWND window);
void UntagWindow(HWND window);

UINT ActivateMessage();

void BringToFront(HWND window);

}

#endif
