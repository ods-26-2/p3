"""Contorno do P3 para código que fixa o endereço do Kafka (CLAUDE.md, seção 4).

O Python importa "sitecustomize" sozinho na partida quando esta pasta está no PYTHONPATH.
Se ODS_KAFKA_FORCAR_BROKER estiver definido, todo Producer, Consumer e AdminClient do
confluent_kafka criado pelo programa passa a usar esse endereço em "bootstrap.servers",
seja qual for o valor escrito no código. Nada no repositório da equipe é alterado.

Uso no compose:
    environment:
      PYTHONPATH: /p3/kafka_override
      ODS_KAFKA_FORCAR_BROKER: ${KAFKA_BROKER}
    volumes:
      - ../comum/kafka_override:/p3/kafka_override:ro

Desfazer: quando a equipe ler o broker de uma variável de ambiente, tire as três linhas
acima e passe a variável dela.
"""

import os
import sys

_BROKER = os.environ.get("ODS_KAFKA_FORCAR_BROKER", "").strip()

if _BROKER:
    try:
        import confluent_kafka as _ck
    except ImportError:  # o programa não usa Kafka: nada a fazer
        _ck = None

    if _ck is not None:
        def _forcar(conf):
            conf = dict(conf or {})
            antigo = conf.get("bootstrap.servers")
            conf["bootstrap.servers"] = _BROKER
            if antigo and antigo != _BROKER:
                print(f"[P3] bootstrap.servers {antigo} -> {_BROKER} (ODS_KAFKA_FORCAR_BROKER)",
                      file=sys.stderr, flush=True)
            return conf

        def _embrulhar(cls):
            class Embrulho(cls):  # type: ignore[misc, valid-type]
                def __init__(self, conf=None, *args, **kwargs):
                    super().__init__(_forcar(conf), *args, **kwargs)
            Embrulho.__name__ = cls.__name__
            Embrulho.__qualname__ = cls.__qualname__
            return Embrulho

        _ck.Producer = _embrulhar(_ck.Producer)
        _ck.Consumer = _embrulhar(_ck.Consumer)
        try:
            import confluent_kafka.admin as _adm
            _adm.AdminClient = _embrulhar(_adm.AdminClient)
            _ck.admin.AdminClient = _adm.AdminClient
        except Exception:
            pass
