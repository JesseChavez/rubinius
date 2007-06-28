#include "shotgun.h"
#include "object.h"
#include <stdlib.h>
#include <string.h>

OBJECT bytearray_new(STATE, int size) {
  int words;
  OBJECT obj;
  
  assert(size >= 0);
  
  words = size / REFSIZE;
  if(size % REFSIZE != 0) {
    words += 1;
  }
  
  assert(words >= 0);
  
  obj = bytearray_allocate_with_extra(state, words);
  object_make_byte_storage(state, obj);
  object_initialize_bytes(state, obj);
  return obj;
}

char *bytearray_as_string(STATE, OBJECT self) {
  char *str;
  char *out;
  int sz;
  
  str = (char*)bytearray_byte_address(state, self);
  
  sz = NUM_FIELDS(self) * REFSIZE;
  out = malloc(sizeof(char) * sz);
  
  memcpy(out, str, sz);
  
  return out;
}
