// Lecture du SMC (System Management Controller) : ventilateurs et sondes de température.
//
// Implémentation propre à Aman Check de l'interface du client utilisateur AppleSMC, la même que celle
// qu'utilisent les outils de surveillance (sélecteur 2, structure de 80 octets). Lecture seule : aucune
// fonction d'écriture n'existe ici. Les clés lues sont décrites dans Sources/AmanCore/SMC.swift.
#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Ouvre une connexion au service AppleSMC. Renvoie 0 si le service n'existe pas ou refuse l'ouverture.
uint32_t aman_smc_open(void);

void aman_smc_close(uint32_t connection);

/// Lit une clé (4 caractères ASCII). `type` reçoit le type SMC (« fpe2 », « flt »…) en 4 caractères + NUL,
/// `bytes` au plus 32 octets, `size` leur nombre. Renvoie 0 en cas de succès.
int aman_smc_read(uint32_t connection, const char *key, char type[5], uint8_t bytes[32], uint32_t *size);

/// Clé numéro `index` (0 ≤ index < valeur de la clé « #KEY »), en 4 caractères + NUL. Renvoie 0 en cas de succès.
int aman_smc_key_at(uint32_t connection, uint32_t index, char key[5]);

#ifdef __cplusplus
}
#endif

#endif
