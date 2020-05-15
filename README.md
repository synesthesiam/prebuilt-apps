# Pre-Built Apps

Docker [buildx](https://docs.docker.com/buildx/working-with-buildx/) compilation of applications used by [Rhasspy](https://github.com/rhasspy) and [voice2json](https://voice2json.org).

## Applications

* Speech to text
    * [Julius](https://github.com/julius-speech/julius)
    * [Kaldi](https://kaldi-asr.org)
        * Not supported on `arm/v6`
* Language modeling
    * [KenLM](https://kheafield.com/code/kenlm/)
* Grapheme to phoneme
    * [Phonetisaurus](https://github.com/AdolfVonKleist/Phonetisaurus)

## Platforms

* `amd64` (desktop/laptop/server)
* `arm/v7` (Raspberry Pi 2/3)
* `arm64` (Raspberry Pi 3+/4)
* `arm/v6` (Raspberry Pi 0/1)

## Building

Set the `DOCKER_REGISTRY` environment variable to your local Docker registry (needed for manifest support). Make sure to include a final `/`

```bash
$ git clone https://github.com/synesthesiam/prebuilt-apps.git
$ cd prebuilt-apps/
$ make
```

This may take all day and all night. Artifacts will be in the `dist/` directory.
