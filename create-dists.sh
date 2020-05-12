#!/usr/bin/env bash
PLATFORMS="$1"
TAG="$2"

mkdir -p dist
while IFS=','; read -ra PLATFORM_ARRAY; do
    for p in "${PLATFORM_ARRAY[@]}"; do
        p_noslash="$(echo ${p} | sed -e 's|linux/||' | tr -d '/')"
        docker pull --platform "${p}" "${TAG}"

        # Julius
        docker run -i --platform "${p}" "${TAG}" cat /julius.tar.gz > "dist/julius-4.5_${p_noslash}.tar.gz"

        # KenLM
        docker run -i --platform "${p}" "${TAG}" cat /kenlm.tar.gz > "dist/kenlm-20200308_${p_noslash}.tar.gz"

        # Opengrm
        docker run -i --platform "${p}" "${TAG}" cat /opengrm.tar.gz > "dist/opengrm-1.3.4_${p_noslash}.tar.gz"

        # Phonetisaurus
        docker run -i --platform "${p}" "${TAG}" cat /phonetisaurus.tar.gz > "dist/phonetisaurus-2019_${p_noslash}.tar.gz"

        # Kaldi
        docker run -i --platform "${p}" "${TAG}" cat /kaldi.tar.gz > "dist/kaldi-2020_${p_noslash}.tar.gz"
    done
done <<< "${PLATFORMS}"
