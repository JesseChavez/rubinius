#include "instructions/passed_blockarg.hpp"

namespace rubinius {
  namespace interpreter {
    intptr_t passed_blockarg(STATE, CallFrame* call_frame, intptr_t const opcodes[]) {
      intptr_t count = argument(0);

      instructions::passed_blockarg(state, call_frame, count);

      call_frame->next_ip(instructions::data_passed_blockarg.width);
      return ((Instruction)opcodes[call_frame->ip()])(state, call_frame, opcodes);
    }
  }
}
