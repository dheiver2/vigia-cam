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
