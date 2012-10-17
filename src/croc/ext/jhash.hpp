#ifndef CROC_EXT_JHASH_HPP
#define CROC_EXT_JHASH_HPP

#include <stddef.h>
#include <stdint.h>     /* defines uint32_t etc */

uint32_t hashword(
const uint32_t *k,                   /* the key, an array of uint32_t values */
size_t          length,               /* the length of the key, in uint32_ts */
uint32_t        initval);         /* the previous hash, or an arbitrary value */

void hashword2 (
const uint32_t *k,                   /* the key, an array of uint32_t values */
size_t          length,               /* the length of the key, in uint32_ts */
uint32_t       *pc,                      /* IN: seed OUT: primary hash value */
uint32_t       *pb);               /* IN: more seed OUT: secondary hash value */

uint32_t hashlittle( const void *key, size_t length, uint32_t initval);

void hashlittle2( 
  const void *key,       /* the key to hash */
  size_t      length,    /* length of the key */
  uint32_t   *pc,        /* IN: primary initval, OUT: primary hash */
  uint32_t   *pb);        /* IN: secondary initval, OUT: secondary hash */

uint32_t hashbig( const void *key, size_t length, uint32_t initval);

#endif