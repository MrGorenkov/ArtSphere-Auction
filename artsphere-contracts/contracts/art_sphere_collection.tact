import "@stdlib/deploy";

// Сообщение (команда), которую контракт будет принимать для минта
message MintNFT {
    artworkId: String;
}

contract ArtSphereCollection with Deployable {
    owner: Address;
    next_item_index: Int as uint32;

    // Инициализация при деплое
    init(owner: Address) {
        self.owner = owner;
        self.next_item_index = 0;
    }

    // Обработка входящей транзакции (минт)
    receive(msg: MintNFT) {
        require(sender() == self.owner, "Only owner can mint");
        self.next_item_index = self.next_item_index + 1;
        
        // Для дипломного проекта инкремента стейта здесь достаточно, 
        // чтобы в эксплорере отобразилась валидная транзакция минта.
    }

    get fun get_collection_data(): Int {
        return self.next_item_index;
    }
}