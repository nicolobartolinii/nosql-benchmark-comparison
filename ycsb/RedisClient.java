// site/ycsb/db/RedisClient.java (Corretto Stile)

/**
 * Copyright (c) 2012 YCSB contributors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. See accompanying
 * LICENSE file.
 */

 package site.ycsb.db;

 import site.ycsb.ByteIterator;
 import site.ycsb.DB;
 import site.ycsb.DBException;
 import site.ycsb.Status;
 import site.ycsb.StringByteIterator;
 
 // import redis.clients.jedis.BasicCommands;
 import redis.clients.jedis.HostAndPort;
 import redis.clients.jedis.Jedis;
 import redis.clients.jedis.JedisCluster;
 import redis.clients.jedis.JedisCommands;
 import redis.clients.jedis.Protocol;
 import redis.clients.jedis.exceptions.JedisException;
 import org.apache.commons.pool2.impl.GenericObjectPoolConfig;
 
 import java.io.Closeable;
 import java.io.IOException;
 import java.util.HashMap;
 import java.util.Map;
 import java.util.HashSet;
 import java.util.Iterator;
 import java.util.List;
 import java.util.Properties;
 import java.util.Set;
 import java.util.Vector;
 
 /**
  * YCSB binding for <a href="http://redis.io/">Redis</a>.
  *
  * See {@code redis/README.md} for details.
  */
 public class RedisClient extends DB {
 
   private JedisCommands jedis;
 
   public static final String HOST_PROPERTY = "redis.host";
   public static final String PORT_PROPERTY = "redis.port";
   public static final String PASSWORD_PROPERTY = "redis.password";
   public static final String CLUSTER_PROPERTY = "redis.cluster";
   public static final String HOSTS_PROPERTY = "redis.hosts";
   public static final String TIMEOUT_PROPERTY = "redis.timeout";
   public static final String MAX_ATTEMPTS_PROPERTY = "redis.maxattempts";
 
   public static final String INDEX_KEY = "_indices";
 
   @Override
   public void init() throws DBException {
     Properties props = getProperties();
     int port;
 
     String portString = props.getProperty(PORT_PROPERTY);
     if (portString != null) {
       port = Integer.parseInt(portString);
     } else {
       port = Protocol.DEFAULT_PORT;
     }
 
     boolean clusterEnabled = Boolean.parseBoolean(props.getProperty(CLUSTER_PROPERTY, "false"));
 
     try {
       if (clusterEnabled) {
         System.out.println("INFO: Modalità Cluster Redis abilitata.");
         Set<HostAndPort> jedisClusterNodes = new HashSet<>();
         String redisHosts = props.getProperty(HOSTS_PROPERTY);
         if (redisHosts == null || redisHosts.trim().isEmpty()) {
           throw new DBException(
               String.format("Proprietà richiesta '%s' mancante o vuota per la modalità cluster.", HOSTS_PROPERTY)
           );
         }
         System.out.println("INFO: Parsing host Redis: " + redisHosts);
 
         String[] hosts = redisHosts.split(",");
         for (String hostPort : hosts) {
           hostPort = hostPort.trim();
           if (hostPort.isEmpty()) {
             continue;
           }
 
           String[] hostAndPort = hostPort.split(":");
           if (hostAndPort.length != 2) {
             throw new DBException(
                 String.format("Host '%s' non valido. Formato richiesto: 'host:port'.", hostPort)
             );
           }
 
           String host = hostAndPort[0].trim();
           String portStr = hostAndPort[1].trim();
 
           if (host == null || host.isEmpty()) {
              throw new DBException(
                  String.format("Host nullo o vuoto trovato in '%s'.", hostPort)
              );
           }
           if (portStr == null || portStr.isEmpty()) {
              throw new DBException(
                  String.format("Porta nulla o vuota trovata in '%s'.", hostPort)
              );
           }
 
           try {
             int nodePort = Integer.parseInt(portStr);
             System.out.println("DEBUG: Aggiungo nodo al cluster: " + host + ":" + nodePort);
             jedisClusterNodes.add(new HostAndPort(host, nodePort));
           } catch (NumberFormatException e) {
             throw new DBException(
                 String.format("Porta non valida '%s' per host '%s'.", portStr, host), e
             );
           }
         }
 
         if (jedisClusterNodes.isEmpty()) {
            throw new DBException(String.format("Nessun nodo valido trovato nella proprietà '%s': %s",
                                                HOSTS_PROPERTY, redisHosts));
         }
 
         int timeout = Integer.parseInt(props.getProperty(TIMEOUT_PROPERTY, String.valueOf(Protocol.DEFAULT_TIMEOUT)));
         int maxAttempts = Integer.parseInt(props.getProperty(MAX_ATTEMPTS_PROPERTY, "5"));
 
         System.out.println("INFO: Creo JedisCluster con nodi: " + jedisClusterNodes +
                            ", timeout=" + timeout + ", maxAttempts=" + maxAttempts);
 
         jedis = new JedisCluster(jedisClusterNodes, timeout, maxAttempts, new GenericObjectPoolConfig());
 
       } else { // Modalità Standalone
         System.out.println("INFO: Modalità Standalone Redis.");
         String redisHost = props.getProperty(HOST_PROPERTY);
         if (redisHost == null || redisHost.trim().isEmpty()) {
            throw new DBException(
                String.format("Proprietà richiesta '%s' mancante o vuota per modalità standalone.", HOST_PROPERTY)
            );
         }
         System.out.println("INFO: Connessione a Redis standalone: " + redisHost + ":" + port);
         jedis = new Jedis(redisHost, port);
         ((Jedis) jedis).connect();
       }
 
       String password = props.getProperty(PASSWORD_PROPERTY);
       if (password != null && !password.trim().isEmpty()) {
         System.out.println("INFO: Autenticazione con password.");
          if (jedis instanceof Jedis) {
            ((Jedis) jedis).auth(password);
          } else if (jedis instanceof JedisCluster) {
            // Come notato prima, questa parte è problematica per Jedis 2.9.0 Cluster
            System.err.println("WARN: Autenticazione con password per Redis Cluster " +
                               "potrebbe non funzionare correttamente con questa versione di YCSB/Jedis.");
          }
       }
 
     } catch (JedisException e) {
       throw new DBException("Errore durante l'inizializzazione della connessione Redis: " + e.getMessage(), e);
     } catch (Exception e) {
        throw new DBException("Errore imprevisto durante l'inizializzazione di RedisClient: " + e.getMessage(), e);
     }
 
     System.out.println("INFO: RedisClient inizializzato correttamente.");
   }
 
   @Override
   public void cleanup() throws DBException {
     if (jedis instanceof Closeable) {
       try {
         ((Closeable) jedis).close();
          System.out.println("INFO: Connessione Redis chiusa.");
       } catch (IOException e) {
         System.err.println("WARN: Errore durante la chiusura della connessione Redis: " + e.getMessage());
       }
     }
   }
 
   private double hash(String key) {
     return (double) key.hashCode();
   }
 
   @Override
   public Status read(String table, String key, Set<String> fields,
       Map<String, ByteIterator> result) {
     try {
       if (fields == null || fields.isEmpty()) {
         Map<String, String> values = jedis.hgetAll(key);
         if (values == null || values.isEmpty()) {
           return Status.NOT_FOUND;
         }
         StringByteIterator.putAllAsByteIterators(result, values);
       } else {
         String[] fieldArray = fields.toArray(new String[0]);
         List<String> values = jedis.hmget(key, fieldArray);
         Iterator<String> fieldIterator = fields.iterator();
         Iterator<String> valueIterator = values.iterator();
         boolean valueFound = false;
         while (fieldIterator.hasNext() && valueIterator.hasNext()) {
           String fieldValue = valueIterator.next();
           if (fieldValue != null) {
             result.put(fieldIterator.next(), new StringByteIterator(fieldValue));
             valueFound = true;
           } else {
              fieldIterator.next();
           }
         }
         if (!valueFound) {
            return Status.NOT_FOUND;
         }
       }
       return Status.OK;
     } catch (JedisException e) {
       System.err.println("ERROR: Errore Redis durante READ per chiave " + key + ": " + e.getMessage());
       return Status.ERROR;
     }
   }
 
   @Override
   public Status insert(String table, String key,
       Map<String, ByteIterator> values) {
     try {
       if (jedis.hmset(key, StringByteIterator.getStringMap(values)).equalsIgnoreCase("OK")) {
         // jedis.zadd(INDEX_KEY, hash(key), key); // SCAN disabilitato
         return Status.OK;
       } else {
          System.err.println("ERROR: hmset per INSERT su chiave " + key + " non ha ritornato OK.");
         return Status.ERROR;
       }
     } catch (JedisException e) {
       System.err.println("ERROR: Errore Redis durante INSERT per chiave " + key + ": " + e.getMessage());
       return Status.ERROR;
     }
   }
 
   @Override
   public Status delete(String table, String key) {
     try {
       long delResult = jedis.del(key);
       // long zremResult = jedis.zrem(INDEX_KEY, key); // SCAN disabilitato
       if (delResult >= 0) {
          return Status.OK;
       } else {
          System.err.println("ERROR: del per DELETE su chiave " + key + " ha ritornato un valore imprevisto: " + delResult);
          return Status.ERROR;
       }
     } catch (JedisException e) {
        System.err.println("ERROR: Errore Redis durante DELETE per chiave " + key + ": " + e.getMessage());
        return Status.ERROR;
     }
   }
 
   @Override
   public Status update(String table, String key,
       Map<String, ByteIterator> values) {
     try {
       if (jedis.hmset(key, StringByteIterator.getStringMap(values)).equalsIgnoreCase("OK")) {
         return Status.OK;
       } else {
         System.err.println("ERROR: hmset per UPDATE su chiave " + key + " non ha ritornato OK.");
         return Status.ERROR;
       }
     } catch (JedisException e) {
       System.err.println("ERROR: Errore Redis durante UPDATE per chiave " + key + ": " + e.getMessage());
       return Status.ERROR;
     }
   }
 
   @Override
   public Status scan(String table, String startkey, int recordcount,
       Set<String> fields, Vector<HashMap<String, ByteIterator>> result) {
     System.err.println("WARN: La funzione SCAN non è supportata o è disabilitata in questa configurazione del RedisClient.");
     return Status.NOT_IMPLEMENTED;
   }
 }