import Foundation

/// Vocabulário do modelo geral (COCO, 80 classes), na ordem do índice de saída.
///
/// Morava dentro de `DetectorService`, que importa Vision/CoreML e por isso não
/// compila fora do app — o vocabulário é dado de domínio puro e agora pode ser
/// consultado (e testado) sem nada de ML carregado.
enum ClassesCOCO {
    static let nomes = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck",
        "boat","traffic light","fire hydrant","stop sign","parking meter","bench",
        "bird","cat","dog","horse","sheep","cow","elephant","bear","zebra",
        "giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee",
        "skis","snowboard","sports ball","kite","baseball bat","baseball glove",
        "skateboard","surfboard","tennis racket","bottle","wine glass","cup",
        "fork","knife","spoon","bowl","banana","apple","sandwich","orange",
        "broccoli","carrot","hot dog","pizza","donut","cake","chair","couch",
        "potted plant","bed","dining table","toilet","tv","laptop","mouse",
        "remote","keyboard","cell phone","microwave","oven","toaster","sink",
        "refrigerator","book","clock","vase","scissors","teddy bear",
        "hair drier","toothbrush"
    ]

    static func nome(indice: Int) -> String? {
        nomes.indices.contains(indice) ? nomes[indice] : nil
    }

    static func indice(nome: String) -> Int? { nomes.firstIndex(of: nome) }
}

/// Tradução PT-BR de TODAS as classes exibidas ao operador (COCO + EPI).
///
/// Fonte única: overlay dos cards, eventos e relatórios devem passar por
/// `ClassesPT.pt(_:)` em vez de mostrar o nome cru do modelo. Os nomes em
/// inglês continuam sendo a chave interna (regras de alarme, banco, contadores)
/// — só a EXIBIÇÃO é traduzida, então mudar tradução nunca quebra dado antigo.
enum ClassesPT {
    static let mapa: [String: String] = [
        // COCO (80)
        "person": "pessoa", "bicycle": "bicicleta", "car": "carro",
        "motorcycle": "moto", "airplane": "avião", "bus": "ônibus",
        "train": "trem", "truck": "caminhão", "boat": "barco",
        "traffic light": "semáforo", "fire hydrant": "hidrante",
        "stop sign": "placa de pare", "parking meter": "parquímetro",
        "bench": "banco (assento)", "bird": "pássaro", "cat": "gato",
        "dog": "cachorro", "horse": "cavalo", "sheep": "ovelha",
        "cow": "vaca", "elephant": "elefante", "bear": "urso",
        "zebra": "zebra", "giraffe": "girafa", "backpack": "mochila",
        "umbrella": "guarda-chuva", "handbag": "bolsa", "tie": "gravata",
        "suitcase": "mala", "frisbee": "frisbee", "skis": "esquis",
        "snowboard": "snowboard", "sports ball": "bola",
        "kite": "pipa", "baseball bat": "taco de beisebol",
        "baseball glove": "luva de beisebol", "skateboard": "skate",
        "surfboard": "prancha de surfe", "tennis racket": "raquete",
        "bottle": "garrafa", "wine glass": "taça", "cup": "copo",
        "fork": "garfo", "knife": "faca", "spoon": "colher",
        "bowl": "tigela", "banana": "banana", "apple": "maçã",
        "sandwich": "sanduíche", "orange": "laranja",
        "broccoli": "brócolis", "carrot": "cenoura",
        "hot dog": "cachorro-quente", "pizza": "pizza", "donut": "rosquinha",
        "cake": "bolo", "chair": "cadeira", "couch": "sofá",
        "potted plant": "vaso de planta", "bed": "cama",
        "dining table": "mesa", "toilet": "vaso sanitário", "tv": "TV",
        "laptop": "notebook", "mouse": "mouse", "remote": "controle remoto",
        "keyboard": "teclado", "cell phone": "celular",
        "microwave": "micro-ondas", "oven": "forno", "toaster": "torradeira",
        "sink": "pia", "refrigerator": "geladeira", "book": "livro",
        "clock": "relógio", "vase": "vaso", "scissors": "tesoura",
        "teddy bear": "urso de pelúcia", "hair drier": "secador",
        "toothbrush": "escova de dentes",
        // EPI (10)
        "Hardhat": "capacete", "Mask": "máscara",
        "NO-Hardhat": "SEM capacete", "NO-Mask": "SEM máscara",
        "NO-Safety Vest": "SEM colete", "Person": "pessoa",
        "Safety Cone": "cone", "Safety Vest": "colete",
        "machinery": "maquinário", "vehicle": "veículo"
    ]

    /// Nome de exibição em PT; devolve o original se não mapeado (nunca vazio).
    static func pt(_ nome: String) -> String { mapa[nome] ?? nome }
}

/// Vocabulário do modelo de EPI (`ppe.mlpackage`), na ordem do índice de saída
/// (confirmada via `model.names` no export ultralytics).
enum ClassesEPI {
    static let nomes = [
        "Hardhat", "Mask", "NO-Hardhat", "NO-Mask", "NO-Safety Vest",
        "Person", "Safety Cone", "Safety Vest", "machinery", "vehicle"
    ]

    static func nome(indice: Int) -> String? {
        nomes.indices.contains(indice) ? nomes[indice] : nil
    }

    static func indice(nome: String) -> Int? { nomes.firstIndex(of: nome) }
}
