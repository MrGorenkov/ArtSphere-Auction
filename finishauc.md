docker exec nftarts-db psql -U nftarts -d nftarts_db -c \
  "SELECT a.id, ar.title, a.current_bid, a.bid_step FROM auctions a JOIN artworks ar ON ar.id=a.artwork_id WHERE a.status='active' ORDER BY ar.title LIMIT 10;"

docker exec nftarts-db psql -U nftarts -d nftarts_db -c \
  "UPDATE auctions SET end_time = NOW() + INTERVAL '20 seconds' WHERE artwork_id = (SELECT id FROM artworks WHERE title = 'Цифровой Закат');"  