import Foundation

/// Groups both annotation and conversation stores together.
class AnnotationStoreContainer: ObservableObject {
    let annotations = AnnotationStore()
    let conversations = ConversationStore()
}
